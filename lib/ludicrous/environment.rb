require 'ludicrous/stack'

module Ludicrous

class Environment
  attr_reader :function
  attr_reader :scope
  attr_accessor :options
  attr_reader :cbase
  attr_accessor :file
  attr_accessor :line

  def initialize(function, options, cbase, scope)
    @function = function
    @options = options
    @cbase = cbase
    @scope = scope
    @scope_stack = []
    @loop_end_labels = []
    @loops = []
    @file = nil
    @line = nil
    @iter = false
  end

  def self.from_outer(function, inner_scope, outer_env)
    return self.new(
        function,
        outer_env.options,
        outer_env.cbase,
        inner_scope)
  end

  def iter(loop, &block)
    iter = @iter
    begin
      @iter = true
      loop(loop, &block)
    ensure
      @iter = iter
    end
  end

  def return(value)
    if @iter then
      raise "Can't return from inside an iterator"
    else
      @function.insn_return(value)
    end
  end

  def loop(loop)
    @loop_end_labels.push(JIT::Label.new)
    @loops.push(loop)

    begin
      retval = yield
    ensure
      @loops.pop
      @function.insn_label(@loop_end_labels.pop)
    end
    return retval
  end

  def redo
    @loops[-1].redo
  end

  def next
    @function.insn_branch(@loop_end_labels[-1])
  end

  def break
    @loops[-1].break
  end

  # Find a constant, searching the environment's cref
  def get_constant(vid)
    # TODO: search whole const ref list, not just a single class
    # TODO: set source before calling function
    return @function.rb_const_get(@cbase, vid)
  end

  # Search the environment's cref to determine if a constant is defined
  def constant_defined(vid)
    # TODO: set source before calling function
    result = @function.value(JIT::Type::OBJECT)
    @function.if(@function.rb_const_defined(@cbase, vid)) {
      result.store(@function.const(JIT::Type::OBJECT, "constant"))
    } .else {
      result.store(@function.const(JIT::Type::OBJECT, false))
    } .end
    return result
  end
end

class ProgramCounter
  attr_reader :offset

  def initialize
    @offset = 0
  end

  def advance(instruction_length)
    @offset += instruction_length
  end

  def reset()
    @offset = 0
  end
end

class YarvBaseEnvironment < Environment
  attr_reader :stack

  def initialize(function, options, cbase, scope)
    super(function, options, cbase, scope)

    @pc = ProgramCounter.new

    # @stack = YarvStack.new(function)
    @stack = StaticStack.new(function, @pc)
  end
end

class YarvEnvironment < YarvBaseEnvironment
  attr_reader :pc
  attr_reader :sorted_catch_table

  def initialize(function, options, cbase, scope, iseq)
    super(function, options, cbase, scope)

    @iseq = iseq

    @labels = {}

    init_catch_table(iseq)
  end

  def init_catch_table(iseq)
    @sorted_catch_table = iseq.catch_table.sort { |lhs, rhs|
      [ lhs.start, lhs.end ] <=> [ rhs.start, rhs.end ]
    }

    @catch_table_tag = {}
    @sorted_catch_table.each do |catch_table|
      @catch_table_tag[catch_table] = 
        Ludicrous::VMTag.create(@function)
    end

    @catch_table_state = {}
    @sorted_catch_table.each do |catch_table|
      @catch_table_state[catch_table] = 
        @function.value(JIT::Type::INT)
    end
  end

  def local_variable_name(idx)
    local_table = @iseq.local_iseq.local_table
    local_table_idx = local_table.size - idx + 1
    return local_table[local_table_idx]
  end

  def dyn_variable_name(idx, level)
    iseq = @iseq
    while level > 0 and iseq
      iseq = iseq.parent_iseq
    end

    dyn_table_idx = iseq.local_table.size - idx + 1
    return iseq.local_table[dyn_table_idx]
  end

  def make_label
    # TODO: we don't need to label every offset, only the ones that we
    # might jump to
    @labels[@pc.offset] ||= JIT::Label.new
    @function.insn_label(@labels[@pc.offset])
    scope.local_get(:n)
  end

  def get_label(offset)
    return @labels[offset]
  end

  def branch(offset)
    @labels[offset] ||= JIT::Label.new
    @stack.validate_branch(offset)
    if inside = is_tag_jump(offset) then
      prepare_tag_jump(*inside)
    end
    @function.insn_branch(@labels[offset])
  end

  def branch_consume(offset)
    if @stack.static? then
      @function.insn_branch(@labels[offset])
      # value = stack.pop
      # branch(offset)
      # stack.push(value)
    else
      branch(offset)
    end
  end

  def branch_relative(relative_offset)
    offset = @pc.offset + relative_offset
    branch(offset)
  end

  def branch_relative_if(cond, relative_offset)
    offset = @pc.offset + relative_offset
    @labels[offset] ||= JIT::Label.new
    @stack.validate_branch(offset)
    if inside = is_tag_jump(offset) then
      @function.if(cond) {
        prepare_tag_jump(*inside)
        @function.insn_branch(@labels[offset])
      }
    else
      @function.insn_branch_if(cond, @labels[offset])
    end
  end

  def branch_relative_unless(cond, relative_offset)
    offset = @pc.offset + relative_offset
    @labels[offset] ||= JIT::Label.new
    @stack.validate_branch(offset)
    if inside = is_tag_jump(offset) then
      @function.unless(cond) {
        prepare_tag_jump(*inside)
        @function.insn_branch(@labels[offset])
      }
    else
      @function.insn_branch_if_not(cond, @labels[offset])
    end
  end
 
  def push_tag(tag)
    tag.tag = function.const(JIT::Type::INT, 0)
    tag.prev = function.ruby_current_thread_tag()
    @function.ruby_set_current_thread_tag(tag.ptr)
  end

  def pop_tag(tag)
    @function.ruby_set_current_thread_tag(tag.prev)
  end

  def exec_tag
    # TODO: _setjmp may or may not be right for this platform
    jmp_buf = @function.ruby_current_thread_jmp_buf()
    return @function._setjmp(jmp_buf)
  end

  def with_tag(tag)
    push_tag(tag)
    state = exec_tag
    function.if(state == function.const(JIT::Type::INT, 0)) {
      yield
    }.end
    pop_tag(tag)
    return state
  end

  def with_tag_for(catch_entry)
    tag = @catch_table_tag[catch_entry]
    push_tag(tag)
    state = exec_tag
    @catch_table_state[catch_entry].store(state)
    function.if(state == function.const(JIT::Type::INT, 0)) {
      yield
    }.end
    pop_tag(tag)
    return @catch_table_state[catch_entry]
  end

  def is_tag_jump(offset)
    currently_inside = inside_catch_entries(@pc.offset)
    jumping_inside = inside_catch_entries(offset)

    if currently_inside == jumping_inside then
      return false
    else
      return [ currently_inside, jumping_inside ]
    end
  end

  def prepare_tag_jump(currently_inside, jumping_inside)
    (currently_inside - jumping_inside).reverse.each do |catch_entry|
      tag = @catch_table_tag[catch_entry]
      pop_tag(tag)
    end

    (jumping_inside - currently_inside).each do |catch_entry|
      tag = @catch_table_tag[catch_entry]
      push_tag(tag)
      state = exec_tag
      @catch_table_state[catch_entry].store(state)
    end

    return true
  end

  def inside_catch_entries(offset)
    catch_entries = []
    @sorted_catch_table.each do |catch_entry|
      if offset >= catch_entry.start and offset <= catch_entry.end then
        catch_entries << catch_entry
      end
    end
    return catch_entries
  end
end

end # Ludicrous

