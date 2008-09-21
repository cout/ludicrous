module Ludicrous

class Stack
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
    # Set the new stack pointer
    popn(-1)

    # And assign to the top of the stack
    setn(1, value)
  end

  # Pop a value from the top of the stack and return it
  def pop
    value = topn(1)
    popn(1)
    return value
  end

  def debug_inspect
    idx = @function.value(JIT::Type::INT)
    idx.store(@function.const(JIT::Type::INT, 1))
    @function.debug_print_msg("/--- Stack ---")
    self.each do |value|
      @function.debug_inspect_object value
    end
    @function.debug_print_msg("\\-------------")
  end

  def each
    raise NotImplementedError, "derived class must implement"
  end

  def sync_sp
    raise NotImplementedError, "derived class must implement"
  end

  def topn(n)
    raise NotImplementedError, "derived class must implement"
  end

  def setn(n, value)
    raise NotImplementedError, "derived class must implement"
  end

  def popn(n)
    raise NotImplementedError, "derived class must implement"
  end

  def validate_branch(dest)
    raise NotImplementedError, "derived class must implement"
  end
end

class StaticStack < Stack
  def initialize(function, pc)
    @function = function
    @pc = pc
    @stack = []
    @stack_pc = []
  end

  def sync_sp
    # no-op
  end

  # Get the nth member from the top of the stack (index 1 is the top of
  # the stack)
  def topn(n)
    if JIT::Value === n then
      stack = @function.const(JIT::Type::OBJECT, @stack.dup)
      idx = -n
      return @function.rb_ary_entry(stack, idx)
    else
      raise "Invalid index #{n}" if n < 1
      return @stack[-n]
    end
  end

  # Set the nth member from the top of the stack (index 1 is the top of
  # the stack)
  def setn(n, value)
    raise "Invalid index #{n}" if n < 1
    @stack[-n] = value
    @stack_pc[-n] = @pc.offset
  end

  # Pop n members from the top of the stack (or push -n members onto the
  # stack)
  def popn(n)
    if n < 0 then
      for i in 0...-n do
        @stack.push(nil)
        @stack_pc.push(@pc.offset)
      end
    else
      for i in 0...n do
        @stack.pop
        @stack_pc.pop
      end
    end
  end

  def each
    @stack.reverse.each do |value|
      yield value
    end
  end

  def validate_branch(dest)
    # Validate that there are no items left on the stack that were
    # created inside the loop
    @stack_pc.each do |offset|
      if offset > dest then
        raise "Static stack does not allow branch over dynamic stack operations"
      end
    end

    # TODO: Validate that we don't branch to a spot that immediately
    # pops (not sure how to check this, but I'm pretty sure ruby doesn't
    # generate any code that allows it)
  end
end

class YarvStack < Stack
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

  def each
    last = @size
    @function.while(proc { idx <= last }) {
      yield topn(idx)
      idx.store(idx + @function.const(JIT::Type::INT, 1))
    }.end
  end

  def validate_branch(dest)
    # no-op
  end
end

end # module Ludicrous

