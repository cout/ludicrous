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

module StackMethods
  # Get the top member of the stack
  def top
    return topn(1)
  end

  # Assign to the top member of the stack
  def top=(value)
    setn(1, value)
  end

  # Push a new value to the top of the stack
  def push(value)
    # sync_sp
    # @function.debug_print_msg("pushing")
    # @function.debug_inspect_object(value)
    # @function.debug_print_uint(value)
    # @function.debug_print_msg("sp=")
    # @function.debug_print_ptr(@sp)

    # Assign to the top of the stack
    # setn(0, value)
    @function.insn_store_relative(@sp, 0, value)

    # sync_sp
    # @function.debug_print_msg("top is now")
    # @function.debug_inspect_object(topn(0))
    # @function.debug_print_uint(@function.insn_load_relative(@sp, 0, JIT::Type::OBJECT))
    # @function.debug_print_msg("sp=")
    # @function.debug_print_ptr(@sp)

    # And set the new stack pointer
    popn(-1)

    # @function.debug_print_msg("pushed")
    # @function.debug_inspect_object(topn(-1))
    # @function.debug_inspect_object(topn(0))
    # @function.debug_inspect_object(topn(1))
    # @function.debug_inspect_object(topn(2))
    # @function.debug_inspect_object(topn(3))
    # @function.debug_print_msg("sp=")
    # @function.debug_print_ptr(@sp)
  end

  # Pop a value from the top of the stack and return it
  def pop
    popn(1)
    return topn(0)
  end

  def debug_inspect
    # idx = @function.value(JIT::Type::INT)
    # idx.store(@function.const(JIT::Type::INT, 1))
    # last = @size
    # @function.debug_print_msg("/--- Stack ---")
    # @function.while(proc { idx <= last }) {
    #   @function.debug_print_uint(idx)
    #   @function.debug_inspect_object topn(idx)
    #   idx.store(idx + @function.const(JIT::Type::INT, 1))
    # }.end
    # @function.debug_print_msg("\\-------------")
  end
end

class YarvStack
  include StackMethods

  attr_reader :size

  def initialize(function)
    @function = function
    @spp = function.yarv_spp()
    @sp = @function.insn_load_relative(@spp, 0, JIT::Type::VOID_PTR)
    @size = function.value(JIT::Type::INT)
    @size.store(function.const(JIT::Type::INT, 0))
  end

  # Need to call this function whenever we call into ruby, because
  # otherwise anything we put on the stack will be overwritten
  #
  # TODO: OK, This just flat doesn't work.  The stack is getting
  # overwritten, in spite of sync'ing the stack pointer.  I suspect we
  # may be using the wrong stack.
  #
  # Here's an idea.  I originally decided to use the YARV stack, because
  # in case of an exception, the stack would still be popped properly.
  # This may still be possible with a custom stack, if each stack frame
  # keeps its own stack pointer.  We don't want to allocate a new stack
  # each time, so we still need to call sync_sp in order to write to a
  # "global" stack pointer; this way new frames will know where the top
  # of the stack is.
  #
  # We could even detect someone forgetting to call sync_sp by
  # allocating the entire stack by default and only releasing it if
  # sync_sp is called.
  #
  # Actually, no.  I'm going to disagree with myself here.  I want to
  # keep what I've written above, because it is late, and this might be
  # wrong.  What if when the stack is allocated we store a pointer to
  # sp somewhere?  Then lower stack frames know exactly where sp is.
  # The disadvantage is that sp can no longer be stored in a register.
  # Too bad libjit can't optimize this case. :(
  #
  # There's still the stack unwinding problem to deal with.  What if the
  # stack unwinds, then a new function is called?  It will have the spp
  # of the frame that no longer exists.  Maybe there's no way to avoid
  # the sync_sp call.
  #
  # I really would like to avoid it, beacuse it is annoying and easy to
  # forget.
  #
  # I really don't even want to rewrite all this code.  It's a shame
  # the code below doesn't actually work.  It would save me an afternoon
  # worth of work.
  def sync_sp
    @function.insn_store_relative(@spp, 0, @sp)
  end

  # Get the nth member from the top of the stack (index 1 is the top of
  # the stack)
  def topn(n)
    if n.is_a?(JIT::Value) then
      size = @function.const(JIT::Type::INT, JIT::Type::OBJECT.size)
      offset = -n * size
      return @function.insn_load_elem(@sp, offset, JIT::Type::OBJECT)
    else
      offset = -n * JIT::Type::OBJECT.size
      return @function.insn_load_relative(@sp, offset, JIT::Type::OBJECT)
    end
  end

  # Set the nth member from the top of the stack (index 1 is the top of
  # the stack)
  def setn(n, value)
    offset = -n * JIT::Type::OBJECT.size
    @function.insn_store_relative(@sp, offset, value)
  end

  # Pop n members from the top of the stack (optimization for the case
  # where we don't actually need those values)
  def popn(n)
    @sp.store(@function.insn_add_relative(@sp, n * JIT::Type::OBJECT.size))
    @size.store(@size - @function.const(JIT::Type::INT, n))
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

