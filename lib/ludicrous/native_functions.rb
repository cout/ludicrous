require 'jit/function'
require 'ludicrous.so'

module JIT

class Function
  RB_FUNCALL_FPTR = Ludicrous.function_pointer_of(:rb_funcall)

  def rb_funcall(recv, id, *args)
    if Symbol === id then
      name = "rb_funcall(#{id})"
      id = const(JIT::Type::ID, id)
    else
      name = :rb_funcall
    end

    num_args = const(JIT::Type::INT, args.length)
    param_types = ([ JIT::Type::OBJECT ] * (args.length))
    signature  = JIT::Type.create_signature(
        JIT::ABI::CDECL,
        JIT::Type::OBJECT,
        [ JIT::Type::OBJECT, JIT::Type::ID, JIT::Type::INT ] + param_types)

    return insn_call_native(
        name, RB_FUNCALL_FPTR, signature, 0, recv, id,
        num_args, *args)
  end

  RB_FUNCALL2_FPTR = Ludicrous.function_pointer_of(:rb_funcall2)
  RB_FUNCALL2_SIGNATURE = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT, JIT::Type::ID, JIT::Type::INT, JIT::Type::VOID_PTR ])

  def rb_funcall2(recv, id, argc, argv)
    id = const(JIT::Type::ID, id) if Symbol === id
    return insn_call_native(
        :rb_funcall2, RB_FUNCALL2_FPTR, RB_FUNCALL2_SIGNATURE, 0, recv, id, argc,
        argv)
  end

  RB_FUNCALL3_FPTR = Ludicrous.function_pointer_of(:rb_funcall3)
  RB_FUNCALL3_SIGNATURE = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT, JIT::Type::ID, JIT::Type::INT, JIT::Type::VOID_PTR ])

  def rb_funcall3(recv, id, argc, argv)
    id = const(JIT::Type::ID, id) if Symbol === id
    return insn_call_native(
        :rb_funcall3, RB_FUNCALL3_FPTR, RB_FUNCALL3_SIGNATURE, 0, recv,
        id, argc, argv)
  end

  def self.define_native_function(
      name,
      return_type,
      arg_names,
      arg_types)
    fptr = Ludicrous.function_pointer_of(name)
    signature = JIT::Type.create_signature(
        JIT::ABI::CDECL,
        return_type,
        arg_types)

    name_up = name.to_s.upcase
    comma = arg_names.size > 0 ? ',' : ''
    self.const_set("#{name_up}_FPTR", fptr)
    self.const_set("#{name_up}_SIGNATURE", signature)

    lineno = __LINE__ + 2
    str = <<-END
      def #{name}(#{arg_names.join(', ')})
        insn_call_native(
            :#{name}, #{name_up}_FPTR, #{name_up}_SIGNATURE, 0#{comma}
            #{arg_names.join(', ')})
      end
    END
    eval(str, nil, __FILE__, lineno)
  end

  define_native_function(
      :rb_call_super,
      JIT::Type::OBJECT,
      [ :argc, :argv ],
      [ JIT::Type::INT, JIT::Type::VOID_PTR ])

  define_native_function(
      :rb_add_method,
      JIT::Type::VOID,
      [ :klass, :mid, :body, :noex ],
      [ JIT::Type::OBJECT, JIT::Type::ID, JIT::Type::OBJECT, JIT::Type::INT ])

  define_native_function(
      :rb_obj_is_kind_of,
      JIT::Type::OBJECT,
      [ :obj, :klass ],
      [ JIT::Type::OBJECT, JIT::Type::OBJECT ])

  define_native_function(
      :rb_ary_new,
      JIT::Type::OBJECT,
      [ ],
      [ ])

  define_native_function(
      :rb_ary_new2,
      JIT::Type::OBJECT,
      [ :size ],
      [ JIT::Type::INT ])

  RB_ARY_NEW3_FPTR = Ludicrous.function_pointer_of(:rb_ary_new3)

  def rb_ary_new3(size, *objs)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::INT ] + [ JIT::Type::OBJECT] * size)
    return insn_call_native(
        :rb_ary_new3, RB_ARY_NEW3_FPTR, signature, 0, size, *objs)
  end

  define_native_function(
      :rb_ary_new4,
      JIT::Type::OBJECT,
      [ :size, :vec ],
      [ JIT::Type::UINT, JIT::Type::VOID_PTR ])

  define_native_function(
      :rb_ary_push,
      JIT::Type::OBJECT,
      [ :array, :obj ],
      [ JIT::Type::OBJECT, JIT::Type::OBJECT ])

  define_native_function(
      :rb_ary_pop,
      JIT::Type::OBJECT,
      [ :array ],
      [ JIT::Type::OBJECT ])

  define_native_function(
      :rb_ary_store,
      JIT::Type::OBJECT,
      [ :array, :idx, :obj ],
      [ JIT::Type::OBJECT, JIT::Type::INT, JIT::Type::OBJECT ])

  def rb_ary_entry(array, idx)
    fptr = Ludicrous.function_pointer_of(:rb_ary_entry)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT, JIT::Type::INT ])
    return insn_call_native(:rb_ary_entry, fptr, signature, 0, array, idx)
  end

  def rb_ary_concat(array1, array2)
    fptr = Ludicrous.function_pointer_of(:rb_ary_concat)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT, JIT::Type::OBJECT ])
    return insn_call_native(:rb_ary_concat, fptr, signature, 0, array1, array2)
  end

  def rb_ary_to_ary(obj)
    fptr = Ludicrous.function_pointer_of(:rb_ary_to_ary)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT ])
    return insn_call_native(:rb_ary_to_ary, fptr, signature, 0, obj)
  end

  def rb_ary_dup(obj)
    fptr = Ludicrous.function_pointer_of(:rb_ary_dup)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT ])
    return insn_call_native(:rb_ary_dup, fptr, signature, 0, obj)
  end

  def rb_str_dup(str)
    fptr = Ludicrous.function_pointer_of(:rb_str_dup)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT ])
    return insn_call_native(:rb_str_dup, fptr, signature, 0, str)
  end

  def rb_str_plus(lhs, rhs)
    fptr = Ludicrous.function_pointer_of(:rb_str_plus)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT, JIT::Type::OBJECT ])
    return insn_call_native(:rb_str_plus, fptr, signature, 0, lhs, rhs)
  end

  def rb_str_concat(str1, str2)
    fptr = Ludicrous.function_pointer_of(:rb_str_concat)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT, JIT::Type::OBJECT ])
    return insn_call_native(:rb_str_concat, fptr, signature, 0, str1, str2)
  end

  def rb_hash_new
    fptr = Ludicrous.function_pointer_of(:rb_hash_new)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ ])
    return insn_call_native(:rb_hash_new, fptr, signature, 0)
  end

  def rb_hash_aset(hash, key, value)
    fptr = Ludicrous.function_pointer_of(:rb_hash_aset)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT, JIT::Type::OBJECT, JIT::Type::OBJECT ])
    return insn_call_native(:rb_hash_aset, fptr, signature, 0, hash, key, value)
  end

  def rb_hash_aref(hash, key)
    fptr = Ludicrous.function_pointer_of(:rb_hash_aref)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT, JIT::Type::OBJECT ])
    return insn_call_native(:rb_hash_aref, fptr, signature, 0, hash, key)
  end

  def rb_range_new(range_begin, range_end, exclude_end)
    fptr = Ludicrous.function_pointer_of(:rb_range_new)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT, JIT::Type::OBJECT, JIT::Type::INT])
    v = insn_call_native(:rb_range_new, fptr, signature, 0, range_begin, range_end, exclude_end)
    return v
  end

  def rb_class_of(obj)
    fptr = Ludicrous.function_pointer_of(:rb_class_of)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT ])
    return insn_call_native(:rb_class_of, fptr, signature, 0, obj)
  end

  def rb_singleton_class(obj)
    fptr = Ludicrous.function_pointer_of(:rb_singleton_class)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT ])
    return insn_call_native(:rb_singleton_class, fptr, signature, 0, obj)
  end

  def rb_id2name(id)
    fptr = Ludicrous.function_pointer_of(:rb_id2name)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::VOID_PTR,
      [ JIT::Type::ID ])
    return insn_call_native(:rb_id2name, fptr, signature, 0, id)
  end

  def rb_ivar_set(obj, id, value)
    fptr = Ludicrous.function_pointer_of(:rb_ivar_set)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT, JIT::Type::ID, JIT::Type::OBJECT ])
    return insn_call_native(:rb_ivar_set, fptr, signature, 0, obj, id, value)
  end

  def rb_ivar_get(obj, id)
    fptr = Ludicrous.function_pointer_of(:rb_ivar_get)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT, JIT::Type::ID ])
    return insn_call_native(:rb_ivar_get, fptr, signature, 0, obj, id)
  end

  def rb_ivar_defined(obj, id)
    fptr = Ludicrous.function_pointer_of(:rb_ivar_defined)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT, JIT::Type::ID ])
    return insn_call_native(:rb_ivar_defined, fptr, signature, 0, obj, id)
  end

  def rb_const_get(klass, id)
    fptr = Ludicrous.function_pointer_of(:rb_const_get)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT, JIT::Type::ID ])
    return insn_call_native(:rb_const_get, fptr, signature, 0, klass, id)
  end

  def rb_const_defined(klass, id)
    fptr = Ludicrous.function_pointer_of(:rb_const_defined)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT, JIT::Type::ID ])
    return insn_call_native(:rb_const_defined, fptr, signature, 0, klass, id)
  end

  def rb_const_defined_from(klass, id)
    fptr = Ludicrous.function_pointer_of(:rb_const_defined_from)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT, JIT::Type::ID ])
    return insn_call_native(:rb_const_defined_from, fptr, signature, 0, klass, id)
  end

  def rb_cvar_set(klass, id, value)
    fptr = Ludicrous.function_pointer_of(:rb_cvar_set)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT, JIT::Type::ID, JIT::Type::OBJECT ])
    return insn_call_native(:rb_cvar_set, fptr, signature, 0, klass, id, value)
  end

  def rb_cvar_get(klass, id)
    fptr = Ludicrous.function_pointer_of(:rb_cvar_get)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT, JIT::Type::ID ])
    return insn_call_native(:rb_cvar_get, fptr, signature, 0, klass, id)
  end

  def rb_cvar_defined(klass, id)
    fptr = Ludicrous.function_pointer_of(:rb_cvar_defined)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT, JIT::Type::ID ])
    return insn_call_native(:rb_cvar_defined, fptr, signature, 0, klass, id)
  end

  def rb_gv_set(name, value)
    fptr = Ludicrous.function_pointer_of(:rb_gv_set)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::VOID_PTR, JIT::Type::OBJECT ])
    return insn_call_native(:rb_gv_set, fptr, signature, 0, name, value)
  end

  def rb_gv_get(name)
    fptr = Ludicrous.function_pointer_of(:rb_gv_get)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::VOID_PTR ])
    return insn_call_native(:rb_gv_get, fptr, signature, 0, name)
  end

  def rb_gvar_defined(global_entry)
    fptr = Ludicrous.function_pointer_of(:rb_gvar_defined)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::VOID_PTR ])
    return insn_call_native(:rb_gvar_defined, fptr, signature, 0, global_entry)
  end

  def rb_global_entry(id)
    fptr = Ludicrous.function_pointer_of(:rb_global_entry)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::VOID_PTR,
      [ JIT::Type::ID ])
    return insn_call_native(:rb_global_entry, fptr, signature, 0, id)
  end

  def rb_yield(value)
    fptr = Ludicrous.function_pointer_of(:rb_yield)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT ])
    return insn_call_native(:rb_yield, fptr, signature, 0, value)
  end

  def rb_yield_splat(values)
    fptr = Ludicrous.function_pointer_of(:rb_yield_splat)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT ])
    return insn_call_native(:rb_yield_splat, fptr, signature, 0, values)
  end

  def rb_block_given_p()
    fptr = Ludicrous.function_pointer_of(:rb_block_given_p)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ ])
    return insn_call_native(:rb_block_given_p, fptr, signature, 0)
  end

  def rb_block_proc()
    fptr = Ludicrous.function_pointer_of(:rb_block_proc)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ ])
    return insn_call_native(:rb_block_proc, fptr, signature, 0)
  end

  def rb_iterate(iter_fptr, iter_env, body_fptr, body_env)
    fptr = Ludicrous.function_pointer_of(:rb_iterate)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::FUNCTION_PTR, JIT::Type::VOID_PTR, JIT::Type::FUNCTION_PTR, JIT::Type::VOID_PTR ])
    return insn_call_native(:rb_iterate, fptr, signature, 0, iter_fptr, iter_env, body_fptr, body_env)
  end

  def rb_proc_new(func, val)
    fptr = Ludicrous.function_pointer_of(:rb_proc_new)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::FUNCTION_PTR, JIT::Type::OBJECT ])
    return insn_call_native(:rb_proc_new, fptr, signature, 0, func, val)
  end

  def rb_iter_break()
    fptr = Ludicrous.function_pointer_of(:rb_iter_break)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ ])
    return insn_call_native(:rb_iter_break, fptr, signature, JIT::Call::NORETURN)
  end

  def rb_ensure(body_fptr, body_env, ensr_fptr, ensr_env)
    fptr = Ludicrous.function_pointer_of(:rb_ensure)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::FUNCTION_PTR, JIT::Type::OBJECT, JIT::Type::FUNCTION_PTR, JIT::Type::OBJECT ])
    return insn_call_native(:rb_ensure, fptr, signature, 0, body_fptr, body_env, ensr_fptr, ensr_env)
  end

  def rb_rescue2(body_fptr, body_env, ensr_fptr, ensr_env, *types)
    fptr = Ludicrous.function_pointer_of(:rb_rescue2)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::FUNCTION_PTR, JIT::Type::OBJECT, JIT::Type::FUNCTION_PTR, JIT::Type::OBJECT ] + \
      [ JIT::Type::OBJECT ] * types.size)
    return insn_call_native(:rb_rescue2, fptr, signature, 0, body_fptr, body_env, ensr_fptr, ensr_env, *types)
  end

  def rb_protect(body_fptr, body_env, state)
    fptr = Ludicrous.function_pointer_of(:rb_protect)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::FUNCTION_PTR, JIT::Type::OBJECT, JIT::Type::FUNCTION_PTR ])
    return insn_call_native(:rb_protect, fptr, signature, 0, body_fptr, body_env, state)
  end

  def rb_jump_tag(state)
    fptr = Ludicrous.function_pointer_of(:rb_jump_tag)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::INT ])
    return insn_call_native(:rb_jump_tag, fptr, signature, JIT::Call::NORETURN, state)
  end

  def rb_uint2inum(uint)
    fptr = Ludicrous.function_pointer_of(:rb_uint2inum)
    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::UINT ])
    return insn_call_native(:rb_uint2inum, fptr, signature, 0, uint)
  end

  def rb_svar(cnt)
    fptr = Ludicrous::function_pointer_of(:rb_svar)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::VOID_PTR,
        [ JIT::Type::UINT ])
    return insn_call_native(:rb_svar, fptr, signature, 0, cnt)
  end

  def rb_reg_nth_match(nth, match)
    fptr = Ludicrous::function_pointer_of(:rb_reg_nth_match)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::OBJECT,
        [ JIT::Type::INT, JIT::Type::OBJECT ])
    return insn_call_native(:rb_reg_nth_match, fptr, signature, 0, nth, match)
  end

  def rb_reg_match(re, str)
    fptr = Ludicrous::function_pointer_of(:rb_reg_match)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::OBJECT,
        [ JIT::Type::OBJECT, JIT::Type::OBJECT ])
    return insn_call_native(:rb_reg_match, fptr, signature, 0, re, str)
  end

  def rb_reg_match2(re)
    fptr = Ludicrous::function_pointer_of(:rb_reg_match2)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::OBJECT,
        [ JIT::Type::OBJECT, JIT::Type::OBJECT ])
    return insn_call_native(:rb_reg_match2, fptr, signature, 0, re)
  end

  def data_wrap_struct(klass, mark, free, sval)
    fptr = Ludicrous::function_pointer_of(:rb_data_object_alloc)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::OBJECT,
        [ JIT::Type::OBJECT, JIT::Type::VOID_PTR, JIT::Type::FUNCTION_PTR, JIT::Type::FUNCTION_PTR ])
    return insn_call_native(:rb_data_object_alloc, fptr, signature, 0, klass, sval, mark, free)
  end

  def data_make_struct(klass, type, mark, free)
    len = const(JIT::Type::UINT, type.size)
    ptr = ruby_xcalloc(1, len)
    obj = data_wrap_struct(klass, mark, free, ptr)
    return [ ptr, obj ]
  end

  def ruby_xmalloc(len)
    fptr = Ludicrous::function_pointer_of(:ruby_xmalloc)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::OBJECT,
        [ JIT::Type::UINT ])
    return insn_call_native(:ruby_xmalloc, fptr, signature, 0, len)
  end

  def ruby_xcalloc(n, len)
    fptr = Ludicrous::function_pointer_of(:ruby_xcalloc)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::OBJECT,
        [ JIT::Type::INT, JIT::Type::INT ])
    return insn_call_native(:ruby_xcalloc, fptr, signature, 0, n, len)
  end

  def ruby_xfree(ptr)
    fptr = Ludicrous::function_pointer_of(:ruby_xfree)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::OBJECT,
        [ JIT::Type::VOID_PTR ])
    return insn_call_native(:ruby_xfree, fptr, signature, 0, ptr)
  end

  def rb_type(obj)
    result = value(JIT::Type::INT)
    # TODO: use a jump table?
    self.if(obj.is_fixnum) {
      result.store(const(JIT::Type::INT, Ludicrous::T_FIXNUM))
    } .elsif(obj & const(JIT::Type::INT, 2)) {
      self.if(obj == const(JIT::Type::INT, Ludicrous::Qtrue)) { # 2
        result.store(const(JIT::Type::INT, Ludicrous::T_TRUE))
      } .elsif(obj == const(JIT::Type::INT, Ludicrous::Qundef)) { # 6
        result.store(const(JIT::Type::INT, Ludicrous::T_UNDEF))
      } .elsif(obj.is_symbol) {
        result.store(const(JIT::Type::INT, Ludicrous::T_SYMBOL))
      } .end
      # otherwise... ?
    } .else {
      self.if(obj == const(JIT::Type::INT, Ludicrous::Qfalse)) { # 0
        result.store(const(JIT::Type::INT, Ludicrous::T_FALSE))
      } .elsif(obj == const(JIT::Type::INT, Ludicrous::Qnil)) { # 4
        result.store(const(JIT::Type::INT, Ludicrous::T_NIL))
      } .else {
        result.store(obj.builtin_type)
      } .end
    } .end
    return result
  end

  def rb_check_type(obj, type)
    fptr = Ludicrous::function_pointer_of(:rb_check_type)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::OBJECT,
        [ JIT::Type::OBJECT, JIT::Type::INT ])
    return insn_call_native(:rb_check_type, fptr, signature, 0, obj, type)
  end

  def data_get_struct(obj)
    rb_check_type(obj, const(JIT::Type::INT, Ludicrous::T_DATA))
    return ruby_struct_member(:RData, :data, obj)
  end

  def rb_gc_mark(obj)
    fptr = Ludicrous::function_pointer_of(:rb_gc_mark)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::VOID,
        [ JIT::Type::OBJECT ])
    return insn_call_native(:rb_gc_mark, fptr, signature, 0, obj)
  end

  def rb_gc_mark_locations(start_ptr, end_ptr)
    fptr = Ludicrous::function_pointer_of(:rb_gc_mark_locations)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::VOID,
        [ JIT::Type::VOID_PTR, JIT::Type::VOID_PTR ])
    return insn_call_native(:rb_gc_mark_locations, fptr, signature, 0, start_ptr, end_ptr)
  end

  def rb_method_boundp(klass, id, ex)
    fptr = Ludicrous::function_pointer_of(:rb_method_boundp)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::INT,
        [ JIT::Type::OBJECT, JIT::Type::ID, JIT::Type::INT ])
    return insn_call_native(:rb_method_boundp, fptr, signature, 0, klass, id, ex)
  end

  def ruby_frame
    # TODO: this function could be inlined for better performance
    fptr = Ludicrous::function_pointer_of(:ruby_frame)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::VOID_PTR,
        [ ])
    return insn_call_native(:ruby_frame, fptr, signature, 0)
  end

  def ruby_scope
    # TODO: this function could be inlined for better performance
    fptr = Ludicrous::function_pointer_of(:ruby_scope)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::VOID_PTR,
        [ ])
    return insn_call_native(:ruby_scope, fptr, signature, 0)
  end

  def rb_errinfo
    # TODO: this function could be inlined for better performance
    fptr = Ludicrous::function_pointer_of(:rb_errinfo)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::OBJECT,
        [ ])
    return insn_call_native(:rb_errinfo, fptr, signature, 0)
  end

  alias_method :ruby_errinfo, :rb_errinfo

  def block_pass_fcall(recv, mid, args, proc)
    fptr = Ludicrous::function_pointer_of(:block_pass_fcall)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::OBJECT,
        [ JIT::Type::OBJECT, JIT::Type::ID, JIT::Type::OBJECT, JIT::Type::OBJECT ])
    return insn_call_native(:block_pass_fcall, fptr, signature, 0, recv, mid, args, proc)
  end

  def block_pass_call(recv, mid, args, proc)
    fptr = Ludicrous::function_pointer_of(:block_pass_fcall)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::OBJECT,
        [ JIT::Type::OBJECT, JIT::Type::ID, JIT::Type::OBJECT, JIT::Type::OBJECT ])
    return insn_call_native(:block_pass_fcall, fptr, signature, 0, recv, mid, args, proc)
  end

  def ludicrous_splat_iterate_proc(body, val)
    fptr = Ludicrous::function_pointer_of(:ludicrous_splat_iterate_proc)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::OBJECT,
        [ JIT::Type::FUNCTION_PTR, JIT::Type::OBJECT ])
    return insn_call_native(:ludicrous_splat_iterate_proc, fptr, signature, 0, body, val)
  end

  def rb_node_newnode(type, a0, a1, a2)
    if type < Node then
      type = const(JIT::Type::INT, type.type.to_i)
    elsif type.is_a?(Integer) then
      type = const(JIT::Type::INT, type)
    end
      
    fptr = Ludicrous::function_pointer_of(:rb_node_newnode)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::VOID_PTR,
        [ JIT::Type::INT, JIT::Type::VOID_PTR, JIT::Type::VOID_PTR, JIT::Type::VOID_PTR ])
    return insn_call_native(:rb_node_newnode, fptr, signature, 0, type, a0, a1, a2)
  end

  def wrap_node(node)
    fptr = Ludicrous::function_pointer_of(:wrap_node)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::OBJECT,
        [ JIT::Type::VOID_PTR ])
    return insn_call_native(:wrap_node, fptr, signature, 0, node)
  end

  def unwrap_node(object)
    fptr = Ludicrous::function_pointer_of(:unwrap_node)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::VOID_PTR,
        [ JIT::Type::OBJECT ])
    return insn_call_native(:unwrap_node, fptr, signature, 0, object)
  end

  def eval_ruby_node(node, recv, cref)
    fptr = Ludicrous::function_pointer_of(:unwrap_node)
    signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::VOID_PTR,
        [ JIT::Type::VOID_PTR, JIT::Type::OBJECT, JIT::Type::VOID_PTR ])
    return insn_call_native(:unwrap_node, fptr, signature, 0, node, recv, cref)
  end

end # Function

end # JIT

