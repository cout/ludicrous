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

class YarvEnvironment < Environment
  def initialize(function, options, cbase, scope)
    super(function, options, cbase, scope)

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
    return @function.insn_load_relative(@sp, idx, JIT::Type::OBJECT)
  end

  def top=(value)
    @function.insn_store_relative(@sp, 0, value)
  end

  alias_method :set_top, :top=

  def set_topn(idx, value)
    @function.insn_store_relative(@sp, idx, JIT::Type::OBJECT, value)
  end

  def push(value)
    @function.insn_store_relative(@sp, 0, value)
    one = @function.const(JIT::Type::INT, 1)
    @sp += one
  end

  def pop
    one = @function.const(JIT::Type::INT, 1)
    @sp -= one
    top = @function.insn_load_relative(@sp, 0, JIT::Type::OBJECT)
    return top
  end
end

end # Ludicrous

