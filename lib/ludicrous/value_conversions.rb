require 'ludicrous/ruby_types'

module JIT

class Value
  def is_returned=(boolean)
    @is_returned = boolean
  end

  def is_returned
    return defined?(@is_returned) && @is_returned
  end

  def fixnum_flag
    return self.function.const(JIT::Type::INT, 1)
  end

  def is_fixnum
    return self & fixnum_flag
  end

  def int2fix
    one = self.function.const(JIT::Type::INT, 1)
    return (self << one) | fixnum_flag
  end

  def fix2int
    one = self.function.const(JIT::Type::INT, 1)
    return self >> one
  end

  def symbol_flag
    return self.function.const(JIT::Type::INT, 0x0e)
  end

  def is_symbol
    mask = self.function.const(JIT::Type::INT, 0xff)
    return (self & mask) == symbol_flag
  end

  def id2sym
    eight = self.function.const(JIT::Type::INT, 8)
    return (self << eight) | symbol_flag
  end

  def builtin_type
    flags = self.function.ruby_struct_member(:RBasic, :flags, self)
    return flags & self.function.const(JIT::Type::INT, Ludicrous::T_MASK)
  end

  def is_type(type)
    return self.function.rb_type(self) == self.function.const(JIT::Type::INT, type)
  end

  def rtest
    #define RTEST(v) (((VALUE)(v) & ~Qnil) != 0)
    qnil = self.function.const(JIT::Type::OBJECT, nil)
    return self & ~qnil
  end

  def to_rbool
    # 0 (Qfalse) => 0
    # all else => 2 (Qtrue)
    zero = self.function.const(JIT::Type::INT, 0)
    one = self.function.const(JIT::Type::INT, 1)
    return self.neq(zero) << one
  end

  def rnot
    # shl: 0 => 0 (Qfalse); 1 => 2 (Qtrue)
    is_false = self.rtest == self.function.const(JIT::Type::INT, 0)
    return self.function.insn_shl(
        is_false,
        self.function.const(JIT::Type::INT, 1))
  end

  # Array -> self
  # NilClass -> [ nil ]
  # Object -> self.to_a
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

  # [ ] -> nil
  # [ obj ] -> obj
  # [ obj1, obj2, ... ] -> self
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
