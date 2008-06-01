#include <jit/jit.h>
#include <ruby.h>

#ifdef RUBY_VM
#include <ruby/node.h>
#else
#include <env.h>
#include <node.h>
#endif

#include <rubyjit.h>

#ifndef HAVE_RB_ERRINFO
static VALUE rb_errinfo()
{
  return ruby_errinfo;
}
#endif

/* Defined in ruby-internal */
VALUE wrap_node(NODE * n);
NODE * unwrap_node(VALUE v);
VALUE eval_ruby_node(NODE * node, VALUE self, VALUE cref);

static VALUE rb_cFunction;
static VALUE rb_cValue;

struct Member_Info
{
  size_t offset;
  jit_type_t type;
};

static VALUE name_to_function_pointer = Qnil;
static VALUE struct_name_to_member_name_info = Qnil;

/* Given a struct name, the name of a struct member, and a jit pointer,
 * to the struct, return a jit pointer to the member within the struct.
 */
static VALUE function_ruby_struct_member(
    VALUE self, VALUE struct_name, VALUE member_name, VALUE ptr_v)
{
  jit_function_t function;
  Data_Get_Struct(self, struct _jit_function, function);

  VALUE member_name_info = rb_hash_aref(
      struct_name_to_member_name_info, 
      struct_name);
  if(member_name_info == Qnil)
  {
    rb_raise(rb_eArgError, "Invalid struct name");
  }

  VALUE member_info_v = rb_hash_aref(
      member_name_info,
      member_name);
  if(member_info_v == Qnil)
  {
    rb_raise(rb_eArgError, "Invalid member name");
  }

  struct Member_Info * member_info;
  Data_Get_Struct(member_info_v, struct Member_Info, member_info);

  if(!rb_obj_is_kind_of(ptr_v, rb_cValue))
  {
    rb_raise(
        rb_eTypeError,
        "Wrong type for ptr; expected Value but got %s",
        rb_class2name(CLASS_OF(ptr_v)));
  }

  jit_value_t ptr;
  Data_Get_Struct(ptr_v, struct _jit_value, ptr);

  jit_value_t result = jit_insn_load_relative(
      function, ptr, member_info->offset, member_info->type);
  return Data_Wrap_Struct(rb_cValue, 0, 0, result);
}

#ifndef RUBY_VM
/* Return a pointer to the current frame */
static void * ruby_frame_()
{
  return ruby_frame;
}

/* Return a pointer to the current scope */
static void * ruby_scope_()
{
  return ruby_scope;
}

struct Ludicrous_Splat_Iterate_Proc_Data
{
  VALUE (*body)(ANYARGS);
  VALUE val;
};

static VALUE ludicrous_splat_iterate_proc_(VALUE val)
{
  struct Ludicrous_Splat_Iterate_Proc_Data * data =
    (struct Ludicrous_Splat_Iterate_Proc_Data *)val;

  ID varname = rb_intern("ludicrous_splat_iterate_var");

  /* Create a new scope */
  NEWOBJ(scope, struct SCOPE);
  OBJSETUP(scope, 0, T_SCOPE);
  scope->super = ruby_scope->super;
  scope->local_tbl = ALLOC_N(ID, 4);
  scope->local_vars = ALLOC_N(VALUE, 4);
  scope->flags = SCOPE_MALLOC;

  /* Set the names of the scope's local variables */
  scope->local_tbl[0] = 3;
  scope->local_tbl[1] = '_';
  scope->local_tbl[2] = '~';
  scope->local_tbl[3] = varname;

  /* And and their values */
  scope->local_vars[0] = 3;
  scope->local_vars[1] = Qnil;
  scope->local_vars[2] = Qnil;
  scope->local_vars[3] = Qnil;
  ++scope->local_vars;

  scope->local_vars[0] = ruby_scope->local_vars[0]; /* $_ */
  scope->local_vars[1] = ruby_scope->local_vars[1]; /* $~ */

  /* Temporarily set ruby_scope to the new scope, so the proc being
   * created below will pick it up (it will be set back when this
   * function returns) */
  ruby_scope = scope;

  /* Create a new proc */
  VALUE proc = rb_proc_new(
      data->body,
      data->val);

  NODE * * var;
  Data_Get_Struct(proc, NODE *, var);

  /* Set the iterator's assignment node to set a local variable that the
   * iterator's body can retrieve */
  *var = NEW_MASGN(
      0,
      NEW_NODE(
          NODE_LASGN,
          varname,
          0,
          2));

  /* And return the proc */
  return proc;
}

static VALUE ludicrous_splat_iterate_proc(
    VALUE (*body)(ANYARGS),
    VALUE val)
{
  int state;
  struct SCOPE * orig_scope = ruby_scope;
  VALUE proc;

  struct Ludicrous_Splat_Iterate_Proc_Data data = { body, val };

  proc = rb_protect(
      ludicrous_splat_iterate_proc_,
      (VALUE)&data,
      &state);
  ruby_scope = orig_scope;

  if(state != 0)
  {
    rb_jump_tag(state);
  }

  return proc;
}
#endif

static VALUE block_pass_fcall(VALUE recv, ID mid, VALUE args, VALUE proc)
{
  NODE * node = NEW_NODE(
      NODE_BLOCK_PASS,
      0,
      NEW_LIT(proc),
      NEW_FCALL(
          mid,
          NEW_SPLAT(
              NEW_LIT(args))));
  return eval_ruby_node(node, recv, Qnil);
}

static VALUE block_pass_call(VALUE recv, ID mid, VALUE args, VALUE proc)
{
  NODE * node = NEW_NODE(
      NODE_BLOCK_PASS,
      0,
      NEW_LIT(proc),
      NEW_CALL(
          NEW_LIT(recv),
          mid,
          NEW_SPLAT(
              NEW_LIT(args))));
  return eval_ruby_node(node, recv, Qnil);
}

/* Emit jit instructions to set the current sourceline and sourcefile.
 */
static VALUE function_set_ruby_source(VALUE self, VALUE node_v)
{
  NODE * n;
  jit_function_t function;

  Data_Get_Struct(self, struct _jit_function, function);
  Data_Get_Struct(node_v, NODE, n); // TODO: type check

  VALUE value_objects = (VALUE)jit_function_get_meta(function, RJT_VALUE_OBJECTS);

  jit_constant_t c;

  c.type = jit_type_int;
  c.un.int_value = nd_line(n);
  jit_value_t line = jit_value_create_constant(function, &c);

  c.type = jit_type_void_ptr;
  c.un.ptr_value = n->nd_file;
  jit_value_t file = jit_value_create_constant(function, &c);

  c.type = jit_type_void_ptr;
  c.un.ptr_value = n;
#ifndef RUBY_VM
  jit_value_t node = jit_value_create_constant(function, &c);
#endif

  c.type = jit_type_void_ptr;
  c.un.ptr_value = &ruby_sourceline;
  jit_value_t ruby_sourceline_ptr = jit_value_create_constant(function, &c);

  c.type = jit_type_void_ptr;
  c.un.ptr_value = &ruby_sourcefile;
  jit_value_t ruby_sourcefile_ptr = jit_value_create_constant(function, &c);

#ifndef RUBY_VM
  c.type = jit_type_void_ptr;
  c.un.ptr_value = &ruby_current_node;
  jit_value_t ruby_current_node_ptr = jit_value_create_constant(function, &c);
#endif

  jit_insn_store_relative(function, ruby_sourceline_ptr, 0, line);
  jit_insn_store_relative(function, ruby_sourcefile_ptr, 0, file);
#ifndef RUBY_VM
  jit_insn_store_relative(function, ruby_current_node_ptr, 0, node);
#endif

  rb_ary_push(value_objects, node_v);

  return Qnil;
}

/* Given the name of a registered function, return a pointer to it.
 */
static VALUE function_pointer_of(VALUE klass, VALUE function_name)
{
  VALUE v = rb_hash_aref(name_to_function_pointer, function_name);

  if(v == Qnil)
  {
    VALUE name_str = rb_inspect(function_name);;
    rb_raise(
        rb_eArgError,
        "No such function pointer defined: %s",
        STR2CSTR(name_str));
  }

  return v;
}

/* Register a struct member (to be used later by the
 * DEFINE_RUBY_STRUCT_MEMBER macro).
 */
static void add_member_info(
    char const * struct_name,
    char const * member_name,
    size_t offset,
    jit_type_t type)
{
  VALUE array_info = rb_hash_aref(struct_name_to_member_name_info, ID2SYM(rb_intern(struct_name)));
  if(array_info == Qnil)
  {
    array_info = rb_hash_new();
    rb_hash_aset(struct_name_to_member_name_info, ID2SYM(rb_intern(struct_name)), array_info);
  }

  struct Member_Info * member_info;
  VALUE member_info_v = Data_Make_Struct(rb_cObject, struct Member_Info, 0, xfree, member_info);
  member_info->offset = offset;
  member_info->type = type;
  rb_hash_aset(array_info, ID2SYM(rb_intern(member_name)), member_info_v);
}

void Init_ludicrous()
{
  rb_require("jit");

  VALUE rb_mJIT = rb_define_module("JIT");

  rb_cFunction = rb_define_class_under(rb_mJIT, "Function", rb_cObject);
  rb_define_method(rb_cFunction, "set_ruby_source", function_set_ruby_source, 1);
  rb_define_method(rb_cFunction, "ruby_struct_member", function_ruby_struct_member, 3);

  rb_cValue = rb_define_class_under(rb_mJIT, "Value", rb_cObject);

  VALUE rb_mLudicrous = rb_define_module("Ludicrous");
  rb_define_module_function(rb_mLudicrous, "function_pointer_of", function_pointer_of, 1);

  name_to_function_pointer = rb_hash_new();
  rb_gc_register_address(&name_to_function_pointer);

#define DEFINE_FUNCTION_POINTER(name) \
  rb_hash_aset(name_to_function_pointer, ID2SYM(rb_intern(#name)), ULONG2NUM((unsigned long)name))

  DEFINE_FUNCTION_POINTER(rb_funcall);
  DEFINE_FUNCTION_POINTER(rb_funcall2);
  DEFINE_FUNCTION_POINTER(rb_funcall3);
  DEFINE_FUNCTION_POINTER(rb_call_super);
  DEFINE_FUNCTION_POINTER(rb_add_method);
  DEFINE_FUNCTION_POINTER(rb_obj_is_kind_of);
  DEFINE_FUNCTION_POINTER(rb_str_dup);
  DEFINE_FUNCTION_POINTER(rb_str_plus);
  DEFINE_FUNCTION_POINTER(rb_str_concat);
  DEFINE_FUNCTION_POINTER(rb_ary_new);
  DEFINE_FUNCTION_POINTER(rb_ary_new2);
  DEFINE_FUNCTION_POINTER(rb_ary_new3);
  DEFINE_FUNCTION_POINTER(rb_ary_new4);
  DEFINE_FUNCTION_POINTER(rb_ary_push);
  DEFINE_FUNCTION_POINTER(rb_ary_store);
  DEFINE_FUNCTION_POINTER(rb_ary_entry);
  DEFINE_FUNCTION_POINTER(rb_ary_concat);
  DEFINE_FUNCTION_POINTER(rb_ary_to_ary);
  DEFINE_FUNCTION_POINTER(rb_ary_dup);
  DEFINE_FUNCTION_POINTER(rb_hash_new);
  DEFINE_FUNCTION_POINTER(rb_hash_aset);
  DEFINE_FUNCTION_POINTER(rb_hash_aref);
  DEFINE_FUNCTION_POINTER(rb_range_new);
  DEFINE_FUNCTION_POINTER(rb_class_of);
  DEFINE_FUNCTION_POINTER(rb_singleton_class);
  DEFINE_FUNCTION_POINTER(rb_extend_object);
  DEFINE_FUNCTION_POINTER(rb_include_module);
  DEFINE_FUNCTION_POINTER(rb_ivar_set);
  DEFINE_FUNCTION_POINTER(rb_ivar_get);
  DEFINE_FUNCTION_POINTER(rb_ivar_defined);
  DEFINE_FUNCTION_POINTER(rb_const_get);
  DEFINE_FUNCTION_POINTER(rb_const_defined);
  DEFINE_FUNCTION_POINTER(rb_const_defined_from);
  DEFINE_FUNCTION_POINTER(rb_yield);
  DEFINE_FUNCTION_POINTER(rb_yield_splat);
  DEFINE_FUNCTION_POINTER(rb_block_given_p);
  DEFINE_FUNCTION_POINTER(rb_block_proc);
  DEFINE_FUNCTION_POINTER(rb_iterate);
  DEFINE_FUNCTION_POINTER(rb_proc_new);
  DEFINE_FUNCTION_POINTER(rb_iter_break);
  DEFINE_FUNCTION_POINTER(rb_ensure);
  DEFINE_FUNCTION_POINTER(rb_rescue);
  DEFINE_FUNCTION_POINTER(rb_rescue2);
  DEFINE_FUNCTION_POINTER(rb_protect);
  DEFINE_FUNCTION_POINTER(rb_jump_tag);
  DEFINE_FUNCTION_POINTER(rb_uint2inum);
  DEFINE_FUNCTION_POINTER(rb_cvar_set);
  DEFINE_FUNCTION_POINTER(rb_cvar_get);
  DEFINE_FUNCTION_POINTER(rb_cvar_defined);
  DEFINE_FUNCTION_POINTER(rb_gv_set);
  DEFINE_FUNCTION_POINTER(rb_gv_get);
  DEFINE_FUNCTION_POINTER(rb_gvar_defined);
  DEFINE_FUNCTION_POINTER(rb_global_entry);
  DEFINE_FUNCTION_POINTER(rb_id2name);
  DEFINE_FUNCTION_POINTER(rb_reg_nth_match);
  DEFINE_FUNCTION_POINTER(rb_reg_match);
  DEFINE_FUNCTION_POINTER(rb_reg_match2);
  DEFINE_FUNCTION_POINTER(rb_data_object_alloc);
  DEFINE_FUNCTION_POINTER(rb_type);
  DEFINE_FUNCTION_POINTER(rb_check_type);
  DEFINE_FUNCTION_POINTER(ruby_xmalloc);
  DEFINE_FUNCTION_POINTER(ruby_xcalloc);
  DEFINE_FUNCTION_POINTER(ruby_xrealloc);
  DEFINE_FUNCTION_POINTER(ruby_xfree);
  DEFINE_FUNCTION_POINTER(rb_gc_mark);
  DEFINE_FUNCTION_POINTER(rb_gc_mark_locations);
  DEFINE_FUNCTION_POINTER(rb_method_boundp);

#ifndef RUBY_VM

  DEFINE_FUNCTION_POINTER(rb_svar);
#define ruby_frame ruby_frame_
  DEFINE_FUNCTION_POINTER(ruby_frame);
#undef ruby_frame

#define ruby_scope ruby_scope_
  DEFINE_FUNCTION_POINTER(ruby_scope);
#undef ruby_scope

  DEFINE_FUNCTION_POINTER(ludicrous_splat_iterate_proc);

#endif

  DEFINE_FUNCTION_POINTER(rb_errinfo);

  DEFINE_FUNCTION_POINTER(block_pass_fcall);
  DEFINE_FUNCTION_POINTER(block_pass_call);

  DEFINE_FUNCTION_POINTER(rb_node_newnode);

  /* From ruby-internal */
  rb_require("internal/node");
  DEFINE_FUNCTION_POINTER(wrap_node);
  DEFINE_FUNCTION_POINTER(unwrap_node);
  DEFINE_FUNCTION_POINTER(eval_ruby_node);

  struct_name_to_member_name_info = rb_hash_new();
  rb_gc_register_address(&struct_name_to_member_name_info);

#define DEFINE_RUBY_STRUCT_MEMBER(name, member, type) \
  add_member_info(#name, #member, offsetof(struct name, member), type);

  // TODO: might not be right for 64-bit
 
  DEFINE_RUBY_STRUCT_MEMBER(RBasic, flags, jit_type_uint);
  DEFINE_RUBY_STRUCT_MEMBER(RBasic, klass, jit_type_uint);

#ifdef HAVE_ST_ROBJECT_IV_TBL
  DEFINE_RUBY_STRUCT_MEMBER(RObject, iv_tbl, jit_type_void_ptr);
#endif

#ifdef HAVE_ST_RCLASS_IV_TBL
  DEFINE_RUBY_STRUCT_MEMBER(RClass, iv_tbl, jit_type_void_ptr);
#endif

  DEFINE_RUBY_STRUCT_MEMBER(RClass, m_tbl, jit_type_void_ptr);

#ifdef HAVE_ST_RCLASS_SUPER
  DEFINE_RUBY_STRUCT_MEMBER(RClass, super, jit_type_uint);
#endif

#ifdef HAVE_ST_RFLOAT_VALUE
  DEFINE_RUBY_STRUCT_MEMBER(RFloat, value, jit_type_uint);
#endif

#ifdef HAVE_ST_RSTRING_LEN
  DEFINE_RUBY_STRUCT_MEMBER(RString, len, jit_type_uint);
#endif

#ifdef HAVE_ST_RSTRING_PTR
  DEFINE_RUBY_STRUCT_MEMBER(RString, ptr, jit_type_void_ptr);
#endif
  // TODO: capa, shared

  DEFINE_RUBY_STRUCT_MEMBER(RArray, len, jit_type_int);
  DEFINE_RUBY_STRUCT_MEMBER(RArray, ptr, jit_type_void_ptr);
  // TODO: capa, shared

  DEFINE_RUBY_STRUCT_MEMBER(RRegexp, ptr, jit_type_void_ptr);
  DEFINE_RUBY_STRUCT_MEMBER(RRegexp, len, jit_type_uint);
  DEFINE_RUBY_STRUCT_MEMBER(RRegexp, str, jit_type_void_ptr);

#ifdef HAVE_ST_RHASH_TBL
  DEFINE_RUBY_STRUCT_MEMBER(RHash, tbl, jit_type_void_ptr);
#endif
  DEFINE_RUBY_STRUCT_MEMBER(RHash, iter_lev, jit_type_int);
  DEFINE_RUBY_STRUCT_MEMBER(RHash, ifnone, jit_type_uint);

  DEFINE_RUBY_STRUCT_MEMBER(RFile, fptr, jit_type_void_ptr);

  DEFINE_RUBY_STRUCT_MEMBER(RData, dmark, jit_type_void_ptr); // TODO: function ptr
  DEFINE_RUBY_STRUCT_MEMBER(RData, dfree, jit_type_void_ptr); // TODO: function ptr
  DEFINE_RUBY_STRUCT_MEMBER(RData, data, jit_type_void_ptr);

#ifdef HAVE_TYPE_FRAME
  DEFINE_RUBY_STRUCT_MEMBER(FRAME, self, jit_type_uint);
  DEFINE_RUBY_STRUCT_MEMBER(FRAME, argc, jit_type_int);
  DEFINE_RUBY_STRUCT_MEMBER(FRAME, last_func, jit_type_uint);
  DEFINE_RUBY_STRUCT_MEMBER(FRAME, orig_func, jit_type_uint);
  DEFINE_RUBY_STRUCT_MEMBER(FRAME, last_class, jit_type_uint);
  DEFINE_RUBY_STRUCT_MEMBER(FRAME, prev, jit_type_void_ptr);
  DEFINE_RUBY_STRUCT_MEMBER(FRAME, tmp, jit_type_void_ptr);
  DEFINE_RUBY_STRUCT_MEMBER(FRAME, node, jit_type_void_ptr);
  DEFINE_RUBY_STRUCT_MEMBER(FRAME, iter, jit_type_int);
  DEFINE_RUBY_STRUCT_MEMBER(FRAME, flags, jit_type_int);
  DEFINE_RUBY_STRUCT_MEMBER(FRAME, uniq, jit_type_uint);
#endif

#ifdef HAVE_TYPE_SCOPE
  DEFINE_RUBY_STRUCT_MEMBER(SCOPE, local_tbl, jit_type_void_ptr);
  DEFINE_RUBY_STRUCT_MEMBER(SCOPE, local_vars, jit_type_void_ptr);
  DEFINE_RUBY_STRUCT_MEMBER(SCOPE, flags, jit_type_int);
#endif

  rb_define_const(rb_mLudicrous, "Qundef", UINT2NUM(Qundef));
  rb_define_const(rb_mLudicrous, "Qnil", UINT2NUM(Qnil));
  rb_define_const(rb_mLudicrous, "Qtrue", UINT2NUM(Qtrue));
  rb_define_const(rb_mLudicrous, "Qfalse", UINT2NUM(Qfalse));

  rb_define_const(rb_mLudicrous, "T_NONE", UINT2NUM(T_NONE));
  rb_define_const(rb_mLudicrous, "T_NIL", UINT2NUM(T_NIL));
  rb_define_const(rb_mLudicrous, "T_OBJECT", UINT2NUM(T_OBJECT));
  rb_define_const(rb_mLudicrous, "T_CLASS", UINT2NUM(T_CLASS));
  rb_define_const(rb_mLudicrous, "T_ICLASS", UINT2NUM(T_ICLASS));
  rb_define_const(rb_mLudicrous, "T_MODULE", UINT2NUM(T_MODULE));
  rb_define_const(rb_mLudicrous, "T_FLOAT", UINT2NUM(T_FLOAT));
  rb_define_const(rb_mLudicrous, "T_STRING", UINT2NUM(T_STRING));
  rb_define_const(rb_mLudicrous, "T_REGEXP", UINT2NUM(T_REGEXP));
  rb_define_const(rb_mLudicrous, "T_ARRAY", UINT2NUM(T_ARRAY));
  rb_define_const(rb_mLudicrous, "T_FIXNUM", UINT2NUM(T_FIXNUM));
  rb_define_const(rb_mLudicrous, "T_HASH", UINT2NUM(T_HASH));
  rb_define_const(rb_mLudicrous, "T_STRUCT", UINT2NUM(T_STRUCT));
  rb_define_const(rb_mLudicrous, "T_BIGNUM", UINT2NUM(T_BIGNUM));
  rb_define_const(rb_mLudicrous, "T_FILE", UINT2NUM(T_FILE));
  rb_define_const(rb_mLudicrous, "T_TRUE", UINT2NUM(T_TRUE));
  rb_define_const(rb_mLudicrous, "T_FALSE", UINT2NUM(T_FALSE));
  rb_define_const(rb_mLudicrous, "T_DATA", UINT2NUM(T_DATA));
  rb_define_const(rb_mLudicrous, "T_MATCH", UINT2NUM(T_MATCH));
  rb_define_const(rb_mLudicrous, "T_SYMBOL", UINT2NUM(T_SYMBOL));
  rb_define_const(rb_mLudicrous, "T_UNDEF", UINT2NUM(T_UNDEF));

  rb_define_const(rb_mLudicrous, "T_MASK", UINT2NUM(T_MASK));

  rb_define_const(rb_mLudicrous, "TAG_RETURN", UINT2NUM(0x1));
  rb_define_const(rb_mLudicrous, "TAG_BREAK", UINT2NUM(0x2));
  rb_define_const(rb_mLudicrous, "TAG_NEXT", UINT2NUM(0x3));
  rb_define_const(rb_mLudicrous, "TAG_RETRY", UINT2NUM(0x4));
  rb_define_const(rb_mLudicrous, "TAG_REDO", UINT2NUM(0x5));
  rb_define_const(rb_mLudicrous, "TAG_RAISE", UINT2NUM(0x6));
  rb_define_const(rb_mLudicrous, "TAG_THROW", UINT2NUM(0x7));
  rb_define_const(rb_mLudicrous, "TAG_FATAL", UINT2NUM(0x8));
  rb_define_const(rb_mLudicrous, "TAG_MASK", UINT2NUM(0xf));

  rb_define_const(rb_mLudicrous, "YIELD_FUNC_AVALUE", UINT2NUM(1));
  rb_define_const(rb_mLudicrous, "YIELD_FUNC_SVALUE", UINT2NUM(2));
}

