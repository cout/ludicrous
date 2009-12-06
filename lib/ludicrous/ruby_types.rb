require 'ludicrous/native_functions'

module Ludicrous
  # An abstraction for a ruby RBasic object.  All objects "inherit" from
  # RBasic using C-style inheritance (composition).
  class RBasic < JIT::Value
    # Given a pointer to an RBasic struct, return an RBasic wrapper for
    # the object.
    #
    # +objref+:: a pointer to the RBasic struct 
    def self.wrap(objref)
      value = self.new_value(objref.function, JIT::Type::VOID_PTR)
      value.store(objref)
      return value
    end

    # Returns the +flags+ member of the +RBasic+ struct.
    def flags
      return function.ruby_struct_member(:RBasic, :flags, self)
    end

    # Returns the +klass+ member of the +RBasic+ struct.
    def klass
      return function.ruby_struct_member(:RBasic, :klass, self)
    end
  end

  # A "normal" ruby object (e.g. not a NODE or an immutable immediate
  # value)
  class RObject < RBasic
  end

  # An abstraction for an RArray struct (the C type used to hold an
  # array).
  class RArray < RObject
    # Emits code to retrieve the object reference at position +idx+
    # within the array.
    #
    # +idx+:: the index of the object reference to retrieve.
    def [](idx)
      return function.insn_load_elem(ptr(), idx, JIT::Type::OBJECT)
    end

    # Emits code to set the element at position +idx+ within the array.
    #
    # +idx+:: the index of the object reference to set.
    # +value+:: the new value of the element.
    def []=(idx, value)
      return function.insn_store_elem(ptr(), idx, value)
    end

    # Emits code to concatenate the given array onto this array.
    #
    # +ary+:: the RArray to concatenate
    def concat(ary)
      return self.function.rb_ary_concat(self, ary)
    end

    # Returns a JIT::Value with the length of the array (similar to the
    # C RARRAY_LEN macro).
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

    # Returns a C pointer to the first element of the array (similar to
    # the C RARRAY_PTR macro).
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

