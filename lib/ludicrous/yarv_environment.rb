require 'ludicrous/program_counter'

module Ludicrous

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
  end

  def get_label(offset)
    return @labels[offset]
  end

  def branch(offset)
    @labels[offset] ||= JIT::Label.new
    @stack.validate_branch(offset)
    inside = is_tag_jump(offset)
    if inside then
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
    inside = is_tag_jump(offset)
    if inside then
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
    inside = is_tag_jump(offset)
    if inside then
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
