# Helper methods for operating on ruby object references.
#
# These are essentially re-implementations in ruby of many of the macros
# in ruby.h.
#

require 'ludicrous/ruby_types'

module JIT

class Value
  # Set the is_returned flag on the value.
  #
  # If the result of the last expression in a method is returned (that
  # is, it was the operand of a RETURN node), then there is no need to
  # generate a second return instruction (the RETURN node already
  # generated one).  If the result of the last expression in a method is
  # not returned, then we must explicitly return it by generating an
  # insn_return instruction.
  def is_returned=(boolean)
    @is_returned = boolean
  end

  # Get the value's is_returned flag.
  def is_returned
    return defined?(@is_returned) && @is_returned
  end

  # Return a constant holding the bit pattern for the Fixnum flag (the
  # least significant bit in an object reference indicates whether a
  # given object reference is a Fixnum).
  def Fixnum_flag
    return self.function.const(JIT::Type::INT, 1)
  end

  # Determine if this value holds a Fixnum.
  #
  # Return a constant JIT::Value containing a nonzero value if this
  # value holds a Fixnum or a constant containing 0 otherwise.
  def is_Fixnum
    return self & Fixnum_flag
  end

  # Emit code to convert the value from a C integer to a Fixnum.
  #
  # Returns a JIT::Value holding a Fixnum.
  def int2fix
    one = self.function.const(JIT::Type::INT, 1)
    return (self << one) | Fixnum_flag
  end

  # Emit code to convert the value from a Fixnum to a C integer.
  #
  # Returns a JIT::Value holding a C integer.
  def fix2int
    one = self.function.const(JIT::Type::INT, 1)
    return self >> one
  end

  # Return a constant holding the bit pattern for the symbol flag
  def symbol_flag
    return self.function.const(JIT::Type::INT, 0x0e)
  end

  # Determine if this value holds a Symbol.
  #
  # Return a constant JIT::Value containing a nonzero value if this
  # value holds a Symbol or a constant containing 0 otherwise.
  def is_symbol
    mask = self.function.const(JIT::Type::INT, 0xff)
    return (self & mask) == symbol_flag
  end

  # Convert the value from an ID to a Symbol.
  #
  # Returns a JIT::Value containing a Symbol.
  def id2sym
    eight = self.function.const(JIT::Type::INT, 8)
    return (self << eight) | symbol_flag
  end

  # Get the referenced object's tag indicating the type of its
  # underlying C struct.
  #
  # Returns a JIT::Value containing the builtin_type tag (T_ARRAY,
  # T_OBJECT, etc.).
  def builtin_type
    flags = self.function.ruby_struct_member(:RBasic, :flags, self)
    return flags & self.function.const(JIT::Type::INT, Ludicrous::T_MASK)
  end

  # Determine if this value references an object of the given type.
  #
  # Return a constant JIT::Value containing a nonzero value if this
  # value references an object of the given type, or a constant
  # containing 0 otherwise.
  #
  # +type+:: the type to test for (T_ARRAY, T_OBJECT, etc.)
  def is_type(type)
    return self.function.rb_type(self) == self.function.const(JIT::Type::INT, type)
  end

  # Determine if this objref refers to an object with a true value.
  #
  # Returns a JIT::Value containing a value of 0 if this value is false
  # or nil, a constant containing a nonzero value otherwise.
  def rtest
    #define RTEST(v) (((VALUE)(v) & ~Qnil) != 0)
    qnil = self.function.const(JIT::Type::OBJECT, nil)
    return self & ~qnil
  end

  # Convert the C integer to true or false.
  #
  # Returns a JIT::Value containing true if the C integer has nonzero
  # value or a JIT::Value containing false otherwise.
  def to_rbool
    # 0 (Qfalse) => 0
    # all else => 2 (Qtrue)
    zero = self.function.const(JIT::Type::INT, 0)
    one = self.function.const(JIT::Type::INT, 1)
    return self.neq(zero) << one
  end

  # Invert the truth value of a ruby object.
  #
  # Returns a JIT::Value containing true if the referenced object had a
  # false value or a JIT::Value containing false if the referenced
  # object had a true value.
  def rnot
    # shl: 0 => 0 (Qfalse); 1 => 2 (Qtrue)
    is_false = self.rtest == self.function.const(JIT::Type::INT, 0)
    return self.function.insn_shl(
        is_false,
        self.function.const(JIT::Type::INT, 1))
  end

  # "Splats" the value.
  #
  # A splat operation is as follows:
  # * Array -> self
  # * NilClass -> [ nil ]
  # * Object -> self.to_a
  #
  # Returns a JIT::Value containing the splatted value.
  def splat
    result = self.function.value(JIT::Type::OBJECT)

    self.function.if(self.is_type(Ludicrous::T_ARRAY)) {
      result.store(self)
    } .elsif(self == self.function.const(JIT::Type::OBJECT, nil)) {
      result.store(self.function.rb_ary_new3(1, nil))
    } .else {
      # TODO: Don't call to_a if the method is in the base class,
      # otherwise we'll get a warning
      result.store(self.function.rb_funcall(self, :to_a))
    } .end
    return result
  end

  # "Splats" the avalue.
  #
  # An avalue_splat operation is as follows:
  # * [ ] -> nil
  # * [ obj ] -> obj
  # * [ obj1, obj2, ... ] -> self
  #
  # Returns a JIT::Value containing the splatted value.
  def avalue_splat
    result = self.function.value(JIT::Type::OBJECT)
    array = Ludicrous::RArray.wrap(self)
    num_args = array.len
    function.if(num_args == function.const(JIT::Type::INT, 0)) {
      result.store(self.function.const(JIT::Type::OBJECT, nil))
    } .elsif(num_args == function.const(JIT::Type::INT, 1)) {
      array_ptr = array.ptr
      result.store(function.insn_load_relative(array_ptr, 0, JIT::Type::OBJECT))
    } .else {
      result.store(self)
    } .end
    return result
  end
end

end # JIT
