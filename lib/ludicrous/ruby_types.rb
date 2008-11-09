module Ludicrous
  class RBasic < JIT::Value
    def self.wrap(objref)
      value = self.new_value(objref.function, JIT::Type::VOID_PTR)
      value.store(objref)
      return value
    end

    def flags
      return function.ruby_struct_member(:RBasic, :flags, self)
    end

    def klass
      return function.ruby_struct_member(:RBasic, :klass, self)
    end
  end

  class RObject < RBasic
  end

  class RArray < RObject
    def [](idx)
      return function.insn_load_elem(ptr(), idx, JIT::Type::OBJECT)
    end

    def len
      @len ||= len_
      return @len
    end

    def len_
      if function.have_ruby_struct_member(:RArray, :len) then
        # 1.8
        return function.ruby_struct_member(:RArray, :len, self)
      else
        # 1.9
        len = function.value(:INT)
        function.debug_printf("flags="); function.debug_print_uint(flags)
        function.debug_printf("RARRAY_EMBED_FLAG="); function.debug_print_uint(RARRAY_EMBED_FLAG)
        function.debug_printf("RARRAY_EMBED_LEN_SHIFT="); function.debug_print_uint(RARRAY_EMBED_LEN_SHIFT)
        function.debug_printf("RARRAY_EMBED_LEN_MASK="); function.debug_print_uint(RARRAY_EMBED_LEN_MASK)
        function.if(self.flags & Ludicrous::RARRAY_EMBED_FLAG) {
          len.store(
              (flags >> Ludicrous::RARRAY_EMBED_LEN_SHIFT) &
              (Ludicrous::RARRAY_EMBED_LEN_MASK >>
              Ludicrous::RARRAY_EMBED_LEN_SHIFT))
        }.else {
          len.store(
              function.ruby_struct_member(:RArray, :"as.heap.len", self))
        }.end
        return len
      end
    end
    private :len_

    def ptr
      @ptr ||= ptr_
    end

    def ptr_
      if function.have_ruby_struct_member(:RArray, :ptr) then
        # 1.8
        return function.ruby_struct_member(:RArray, :ptr, self)
      else
        # 1.9
        ptr = function.value(:VOID_PTR)
        function.if(self.flags & Ludicrous::RARRAY_EMBED_FLAG) {
          ptr.store(
              self +
              function.ruby_struct_member_offset(:RArray, :"as.ary"))
        }.else {
          ptr.store(
              function.ruby_struct_member(:RArray, :"as.heap.ptr", self))
        }.end
        return ptr
      end
    end
    private :ptr_
  end
end

