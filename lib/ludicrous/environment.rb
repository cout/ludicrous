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
end

class YarvEnvironment < Environment
  attr_reader :stack
  attr_reader :pc

  def initialize(function, options, cbase, scope, iseq)
    super(function, options, cbase, scope)

    @iseq = iseq

    @pc = ProgramCounter.new

    # @stack = YarvStack.new(function)
    @stack = StaticStack.new(function, @pc)

    @labels = {}
  end

  def local_variable_name(idx)
    local_table_idx = @iseq.local_table.size - idx + 1
    return @iseq.local_table[local_table_idx]
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

  def branch(relative_offset)
    offset = @pc.offset + relative_offset
    @labels[offset] ||= JIT::Label.new
    @stack.validate_branch(offset)
    @function.insn_branch(@labels[offset])
  end

  def branch_if(cond, relative_offset)
    offset = @pc.offset + relative_offset
    @labels[offset] ||= JIT::Label.new
    @stack.validate_branch(offset)
    @function.insn_branch_if(cond, @labels[offset])
  end

  def branch_unless(cond, relative_offset)
    offset = @pc.offset + relative_offset
    @labels[offset] ||= JIT::Label.new
    @stack.validate_branch(offset)
    @function.insn_branch_if_not(cond, @labels[offset])
  end
end

end # Ludicrous

