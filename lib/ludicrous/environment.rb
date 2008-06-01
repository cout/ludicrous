module Ludicrous

class Environment
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
end

class YarvStack
  def initialize(function)
    @function = function
    @spp = function.yarv_spp()
    @sp = @function.insn_load_relative(@spp, 0, JIT::Type::VOID_PTR)
  end

  # Need to call this function whenever we call into ruby, because
  # otherwise anything we put on the stack will be overwritten
  def sync_sp
    @function.insn_store_relative(@spp, 0, @sp)
  end

  def top
    return topn(0)
  end

  def topn(idx)
    return @function.insn_load_relative(@sp, -idx, JIT::Type::OBJECT)
  end

  def top=(value)
    @function.insn_store_relative(@sp, 0, value)
  end

  alias_method :set_top, :top=

  def set_topn(idx, value)
    @function.insn_store_relative(@sp, -idx, JIT::Type::OBJECT, value)
  end

  def push(value)
    @function.insn_store_relative(@sp, 0, value)
    popn(-1)
  end

  def pop
    popn(1)
    return top
  end

  def popn(n)
    @sp.store(@function.insn_add_relative(@sp, n * JIT::Type::OBJECT.size))
    return nil
  end

end

class YarvEnvironment < Environment
  attr_reader :stack
  attr_reader :offset

  def initialize(function, options, cbase, scope, iseq)
    super(function, options, cbase, scope)

    @iseq = iseq

    @stack = YarvStack.new(function)

    @labels = {}
    @offset = 0
  end

  def local_variable_name(idx)
    local_table_idx = @iseq.local_table.size - idx + 1
    return @iseq.local_table[local_table_idx]
  end

  def make_label
    # TODO: we don't need to label every offset, only the ones that we
    # might jump to
    @labels[@offset] ||= JIT::Label.new
    @function.insn_label(@labels[@offset])
  end

  def get_label(offset)
    return @labels[offset]
  end

  def advance(instruction_length)
    @offset += instruction_length
  end

  def branch(relative_offset)
    offset = @offset + relative_offset
    @labels[offset] ||= JIT::Label.new
    @function.insn_branch(@labels[offset])
  end

  def branch_if(cond, relative_offset)
    offset = @offset + relative_offset
    @labels[offset] ||= JIT::Label.new
    @function.insn_branch_if(cond, @labels[offset])
  end
end

end # Ludicrous

