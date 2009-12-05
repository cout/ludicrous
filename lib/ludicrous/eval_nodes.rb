require 'ludicrous/iter_loop'

class Node

def set_source(function)
  # ruby_sourceline = function.ruby_sourceline()
  # n = function.const(JIT::Type::INT, self.nd_line)
  # function.insn_store_relative(ruby_sourceline, 0, n)
  # ruby_sourcefile = function.ruby_sourcefile()
  # file = function.const(JIT::Type::CSTRING, self.nd_file)
  # function.insn_store_relative(ruby_sourcefile, 0, file)
  # function.debug_print_msg("Setting source to #{self.nd_file}:#{self.nd_line}")
  function.set_ruby_source(self)
end

class FALSE
  def ludicrous_compile(function, env)
    return function.const(JIT::Type::OBJECT, false)
  end
end

class TRUE
  def ludicrous_compile(function, env)
    return function.const(JIT::Type::OBJECT, true)
  end
end

class NIL
  def ludicrous_compile(function, env)
    return function.const(JIT::Type::OBJECT, nil)
  end
end

class SELF
  def ludicrous_compile(function, env)
    return env.scope.self
  end
end

def ludicrous_compile_call_dyn(function, env, recv, mid, a)
  id = function.const(JIT::Type::ID, mid)
  num_args = function.ruby_struct_member(:RArray, :len, a)
  array_ptr = function.ruby_struct_member(:RArray, :ptr, a)
  set_source(function)
  return function.rb_funcall3(recv, id, num_args, array_ptr)
end

def ludicrous_compile_call(function, env, recv, mid, args)
  if mid == :class_eval or \
     mid == :module_eval or \
     mid == :instance_eval then
    raise "Can't handle call for #{mid}"
  end

  end_label = JIT::Label.new

  if ARRAY === args or Array === args then
    # number of args known at compile time
    args = args.to_a.map do |arg|
      if JIT::Value === arg then
        arg
      else
        arg.ludicrous_compile(function, env)
      end
    end
  elsif not args then
    # no args, known at compile time
    args = []
  else
    # number of args only known at runtime
    a = args.ludicrous_compile(function, env)
    return ludicrous_compile_call_dyn(function, env, recv, mid, a)
  end

  result = function.value(JIT::Type::OBJECT)

  # TODO: This doesn't handle bignums
  binary_fixnum_operators = {
    :+ => proc { |lhs, rhs| lhs + (rhs & function.const(JIT::Type::INT, ~1)) },
    :- => proc { |lhs, rhs| lhs - (rhs & function.const(JIT::Type::INT, ~1)) },
    :< => proc { |lhs, rhs| lhs < rhs },
    :== => proc { |lhs, rhs| lhs == rhs },
  }

  # TODO: This optimization is only valid if Fixnum#+/- has not been
  # redefined
  if binary_fixnum_operators.include?(mid) then
    if args.length == 1 then
      function.if(recv.is_fixnum) {
        function.if(args[0].is_fixnum) {
          result.store(binary_fixnum_operators[mid].call(recv, args[0]))
          function.insn_branch(end_label)
        } .end
      } .end
    end
  end

  unary_fixnum_operators = {
    :succ => proc { |lhs| lhs + function.const(JIT::Type::INT, 2) },
  }

  if unary_fixnum_operators.include?(mid) then
    if args.length == 0 then
      function.if(recv.is_fixnum) {
        result.store(unary_fixnum_operators[mid].call(recv))
        function.insn_branch(end_label)
      } .end
    end
  end

  binary_string_operators = {
    :+ => proc { |lhs, rhs| function.rb_str_plus(lhs, rhs) }
  }

  if binary_string_operators.include?(mid) then
    if args.length == 1 then
      function.if(recv.is_type(Ludicrous::T_STRING)) {
        result.store(binary_string_operators[mid].call(recv, args[0]))
        function.insn_branch(end_label)
      } .end
    end
  end

  if mid == :[] and args.size == 1 then
    function.if(recv.is_type(Ludicrous::T_ARRAY)) {
      function.if(args[0].is_fixnum) {
        idx = args[0].fix2int
        len = function.ruby_struct_member(:RArray, :len, recv)
        function.if(idx < len) {
          is_ge_zero = idx >= function.const(JIT::Type::INT, 0) # TODO: is this right?
          function.if(is_ge_zero) {
            ptr = function.ruby_struct_member(:RArray, :ptr, recv)
            result.store(function.insn_load_elem(ptr, idx, JIT::Type::OBJECT))
            function.insn_branch(end_label)
          } .end
        } .end
      } .end
    } .elsif(recv.is_type(Ludicrous::T_HASH)) {
      result.store(function.rb_hash_aref(recv, args[0]))
      function.insn_branch(end_label)
    } .end
  end

  if mid == :[]= and args.size == 2 then
    function.if(recv.is_type(Ludicrous::T_ARRAY)) {
      function.if(args[0].is_fixnum) {
        idx = args[0].fix2int
        len = function.ruby_struct_member(:RArray, :len, recv)
        function.if(idx < len) {
          is_ge_zero = idx >= function.const(JIT::Type::INT, 0) # TODO: is this right?
          function.if(is_ge_zero) {
            ptr = function.ruby_struct_member(:RArray, :ptr, recv)
            function.insn_store_elem(ptr, idx, args[1])
            result.store(args[1])
            function.insn_branch(end_label)
          } .end
        } .end
      } .end
    } .elsif(recv.is_type(Ludicrous::T_HASH)) {
      result.store(function.rb_hash_aset(recv, args[0], args[1]))
      function.insn_branch(end_label)
    } .end
  end

  if mid == :<< and args.size == 1 then
    function.if(recv.is_type(Ludicrous::T_ARRAY)) {
      result.store(function.rb_ary_push(recv, args[0]))
      function.insn_branch(end_label)
    } .elsif(recv.is_type(Ludicrous::T_STRING)) {
      result.store(function.rb_str_concat(recv, args[0]))
      function.insn_branch(end_label)
    } .end
  end

  set_source(function)
  result.store(function.rb_funcall(recv, mid, *args))

  function.insn_label(end_label)
  return result
end

class CALL
  def ludicrous_compile(function, env)
    recv = self.recv.ludicrous_compile(function, env)
    mid = self.mid
    args = self.args
    return ludicrous_compile_call(function, env, recv, mid, args)
  end

  def ludicrous_defined(function, env)
    result = function.value(JIT::Type::OBJECT)
    recv = self.recv.ludicrous_compile(function, env) # TODO: catch exceptions
    klass = function.rb_class_of(recv)
    # bound = function.rb_method_boundp(klass, self.mid, 1)
    #function.if(bound) {
    defined = function.rb_funcall(klass, :public_method_defined?, self.mid)
    function.if(defined) {
      result.store(function.const(JIT::Type::OBJECT, "method"))
    } .else {
      result.store(function.const(JIT::Type::OBJECT, false))
    } .end
    # TODO: return false for protected
    # TODO: return false for undef'd
    return result
  end
end

def ludicrous_compile_fcall(function, env, mid, args)
  if mid == :binding or mid == :eval or mid == :set_trace_func then
    raise "Can't handle fcall for #{mid}"
  end

  num_args = function.const(JIT::Type::INT, args.length)
  array_type = JIT::Type.create_struct([ JIT::Type::OBJECT ] * args.length)
  array = function.value(array_type)
  array_ptr = function.insn_address_of(array)
  args.each_with_index do |arg, idx|
    function.insn_store_elem(array_ptr, function.const(JIT::Type::INT, idx), arg)
  end
  set_source(function)
  return function.rb_funcall2(env.scope.self, mid, num_args, array_ptr)
end

def ludicrous_compile_fcall_dyn(function, env, mid, args)
  id = function.const(JIT::Type::ID, mid)
  num_args = function.ruby_struct_member(:RArray, :len, args)
  array_ptr = function.ruby_struct_member(:RArray, :ptr, args)
  set_source(function)
  return function.rb_funcall2(env.scope.self, id, num_args, array_ptr)
end

class FCALL
  def ludicrous_compile(function, env)
    mid = self.mid
    case self.args
    when Node::ARGSCAT, Node::SPLAT
      args = self.args.ludicrous_compile(function, env)
      return ludicrous_compile_fcall_dyn(function, env, mid, args)
    when Node
      args = self.args.to_a.map { |arg| arg.ludicrous_compile(function, env) }
    when false
      args = []
    end
    return ludicrous_compile_fcall(function, env, mid, args)
  end
end

class VCALL
  def ludicrous_compile(function, env)
    retval = function.value(JIT::Type::OBJECT)
    if env.scope.respond_to?(:dyn_defined) then
      has_key = env.scope.dyn_defined(self.mid)
      function.if(has_key) {
        retval.store(env.scope.dyn_get(self.mid))
      } .else {
        retval.store(ludicrous_compile_fcall(function, env, self.mid, []))
      } .end
      return retval
    else
      return ludicrous_compile_fcall(function, env, self.mid, [])
    end
  end

  def ludicrous_defined(function, env)
    result = function.value(JIT::Type::OBJECT)
    klass = function.rb_class_of(env.scope.self)
    bound = function.rb_method_boundp(klass, self.mid, 0)
    function.if(bound) {
      result.store(function.const(JIT::Type::OBJECT, "method"))
    } .else {
      result.store(function.const(JIT::Type::OBJECT, false))
    } .end
    return result
  end
end

class SUPER
  def ludicrous_compile(function, env)
    # TODO: check for disabled method in superclass
    # TODO: check for super called outside of method
    args = self.args.to_a
    num_args = function.const(JIT::Type::INT, args.length)
    array_type = JIT::Array.new(JIT::Type::OBJECT, args.length)
    array = array_type.create(function)
    args.each_with_index do |arg, idx|
      array[idx] = arg.ludicrous_compile(function, env)
    end
    set_source(function)
    return function.rb_call_super(num_args, array.ptr)
  end
end

class ZSUPER
  def ludicrous_compile(function, env)
    argv = env.scope.argv
    array_ptr = function.ruby_struct_member(:RArray, :ptr, argv)
    array_len = function.ruby_struct_member(:RArray, :len, argv)
    set_source(function)
    return function.rb_call_super(array_len, array_ptr)
  end
end

class ATTRASGN
  def ludicrous_compile(function, env)
    mid = self.mid
    if self.args then
      args = self.args.to_a.map { |arg| arg.ludicrous_compile(function, env) }
    else
      # TODO: need get the last evaluated node, I think
      raise "Can't handle ATTRASGN without args"
    end

    if self.recv == 0 then
      recv = env.scope.self
    else
      recv = self.recv.ludicrous_compile(function, env)
    end

    return ludicrous_compile_call(function, env, recv, mid, args)
  end
end

class LASGN
  def ludicrous_compile(function, env)
    value = self.value.ludicrous_compile(function, env)
    return env.scope.local_set(self.vid, value)
  end
end

class LVAR
  def ludicrous_compile(function, env)
    return env.scope.local_get(self.vid)
  end

  def ludicrous_defined(function, env)
    return function.const(JIT::Type::OBJECT, "local-variable")
  end
end

# TODO: DASGN means not current frame (according to ko1), but I think
# this implementation modifies current frame?
class DASGN
  def ludicrous_compile(function, env)
    value = self.value.ludicrous_compile(function, env)
    return env.scope.dyn_set(self.vid, value)
  end
end

class DASGN_CURR
  def ludicrous_compile(function, env)
    if self.value then
      value = self.value.ludicrous_compile(function, env)
    else
      value = function.const(JIT::Type::UINT, Ludicrous::Qundef)
    end
    return env.scope.dyn_set(self.vid, value)
  end
end

class DVAR
  def ludicrous_compile(function, env)
    env.scope.dyn_get(self.vid)
  end

  def ludicrous_defined(function, env)
    return function.const(JIT::Type::OBJECT, "local-variable(in-block)")
  end
end

class IASGN
  def ludicrous_compile(function, env)
    vid = function.const(JIT::Type::ID, self.vid)
    value = self.value.ludicrous_compile(function, env)
    return function.rb_ivar_set(env.scope.self, vid, value)
  end
end

class IVAR
  def ludicrous_compile(function, env)
    vid = function.const(JIT::Type::ID, self.vid)
    return function.rb_ivar_get(env.scope.self, vid)
  end

  def ludicrous_defined(function, env)
    vid = function.const(JIT::Type::ID, self.vid)
    result = function.value(JIT::Type::OBJECT)
    function.if(function.rb_ivar_defined(env.scope.self, vid)) {
      result.store(function.const(JIT::Type::OBJECT, "instance-variable"))
    }.else {
      result.store(function.const(JIT::Type::OBJECT, false))
    }
    return result
  end
end

def ludicrous_assign(function, env, lhs, v)
  case lhs
  when LASGN
    env.scope.local_set(lhs.vid, v)
  when DASGN_CURR
    env.scope.dyn_set(lhs.vid, v)
  when MASGN then
    multi_lhs = lhs.head
    rest_lhs = lhs.args
    v = ludicrous_svalue_to_mrhs(function, env, multi_lhs, v)
    ludicrous_massign(function, env, multi_lhs, rest_lhs, v)
  when 0     # lambda { || ... }
    # TODO: We're treating nil as nothing being passed in, which isn't
    # 100% right
    function.unless(v == function.const(JIT::Type::OBJECT, nil)) {
      function.rb_funcall(
          function.const(JIT::Type::OBJECT, nil),
          :raise,
          function.const(JIT::Type::OBJECT, ArgumentError),
          "Wrong number of arguments to proc"
          )
    } .end
    function.const(JIT::Type::OBJECT, nil)
  when false # lambda { ... }
  else
    raise "Can't handle assignment (lhs=#{lhs.inspect})"
  end
end

def ludicrous_svalue_to_mrhs(function, env, multi_lhs, v)
  if not v then
    return function.rb_ary_new()
  elsif not multi_lhs then
    return function.rb_ary_new3(1, v)
  else
    new_v = function.value(JIT::Type::OBJECT)
    function.if(v.is_type(Ludicrous::T_ARRAY)) {
      new_v.store(v)
    } .else {
      new_v.store(function.rb_ary_new3(1, v))
    } .end
    return new_v
  end
end

def ludicrous_massign(function, env, multi_lhs, rest_lhs, rhs)
  multi_lhs = multi_lhs ? multi_lhs.to_a : []
  set_source(function)
  lhs_len = function.const(JIT::Type::INT, multi_lhs.length)
  # TODO: what if rhs isn't an array?
  rhs_len = function.ruby_struct_member(:RArray, :len, rhs)
  rhs_ptr = function.ruby_struct_member(:RArray, :ptr, rhs)
  multi_lhs.each_with_index do |lhs, idx|
    v = function.value(JIT::Type::OBJECT)
    i = function.const(JIT::Type::INT, idx)

    # TODO: This could be done more efficiently (fewer jumps)
    function.if(i < rhs_len) {
      v.store(function.insn_load_elem(rhs_ptr, i, JIT::Type::OBJECT))
    } .else {
      v.store(function.const(JIT::Type::OBJECT, nil))
    } .end

    ludicrous_assign(function, env, lhs, v)
  end

  if rest_lhs and rest_lhs != -1 then
    i = function.const(JIT::Type::INT, multi_lhs.size)
    v = function.value(JIT::Type::OBJECT)
    function.if(i < rhs_len) {
      # TODO: not 64-bit safe
      v.store(function.rb_ary_new4(
          rhs_len - i,
          rhs_ptr + (i << function.const(JIT::Type::INT, 2))))
    } .else {
      v.store(function.rb_ary_new())
    } .end
    ludicrous_assign(function, env, rest_lhs, v)
  end

  return rhs
end

class MASGN
  def ludicrous_compile(function, env)
    set_source(function)
    multi_lhs = self.head
    rest_lhs = self.args
    rhs = self.value.ludicrous_compile(function, env)
    return ludicrous_massign(function, env, multi_lhs, rest_lhs, rhs)
  end
end

class OP_ASGN1
  def ludicrous_compile(function, env)
    recv = self.recv.ludicrous_compile(function, env)
    index = self.args.body.to_a.map { |n| n.ludicrous_compile(function, env) }
    lhs = ludicrous_compile_call(function, env, recv, :[], index)
    rhs = [ self.args.head ]

    result = lhs
    case self.mid
    when false # OR
      function.unless(lhs.rtest) {
        result.store(self.args.recv.ludicrous_compile(function, env))
      } .end
    when true # AND
      function.if(lhs.rtest) {
        result.store(self.args.recv.ludicrous_compile(function, env))
      } .end
    else
      result.store(ludicrous_compile_call(function, env, lhs, self.mid, rhs))
    end

    ludicrous_compile_call(function, env, recv, :[]=, index + [result])
    return result
  end
end

class OP_ASGN_OR
  def ludicrous_compile(function, env)
    # recv ||= value
    result = function.value(JIT::Type::OBJECT)
    result.store(function.const(JIT::Type::OBJECT, nil))
    if self.aid then
      defined = self.recv.ludicrous_defined(function, env)
    else
      defined = function.const(JIT::Type::INT, 1)
    end
    function.if(defined) {
      result.store(self.recv.ludicrous_compile(function, env))
    } .end
    function.unless(result.rtest) {
      result.store(self.value.ludicrous_compile(function, env))
    } .end
    return result
  end
end

class OP_ASGN_AND
    # recv &&= value
  def ludicrous_compile(function, env)
    result = function.value(JIT::Type::OBJECT)
    result.store(self.recv.ludicrous_compile(function, env))
    function.if(result.rtest) {
      result.store(self.value.ludicrous_compile(function, env))
    } .end
    return result
  end
end

class DEFINED
  def ludicrous_compile(function, env)
    defined = self.head.ludicrous_defined(function, env)
    result = function.value(JIT::Type::OBJECT)
    function.if(defined) {
      result.store(function.rb_str_dup(defined))
    } .else {
      result.store(function.const(JIT::Type::OBJECT, nil))
    } .end
    return result
  end
end

class CONST
  def ludicrous_compile(function, env)
    set_source(function)
    return env.get_constant(self.vid)
  end

  def ludicrous_defined(function, env)
    return env.constant_defined(self.vid)
  end
end

class COLON3
  def ludicrous_compile(function, env)
    set_source(function)
    return function.rb_const_get(Object, self.vid)
  end

  def ludicrous_defined(function, env)
    result = function.value(JIT::Type::OBJECT)
    function.if(function.rb_const_defined_from(Object, self.mid)) {
      result.store(function.const(JIT::Type::OBJECT, "constant"))
    } .else {
      result.store(function.const(JIT::Type::OBJECT, false))
    } .end
    return result
  end
end

class COLON2
  # TODO: This should work for methods AND constants
  def ludicrous_compile(function, env)
    set_source(function)
    klass = self.head.ludicrous_compile(function, env)
    return function.rb_const_get(klass, self.mid)
  end

  def ludicrous_defined(function, env)
    # TODO: don't use rb_const_defined_from with non-module types
    result = function.value(JIT::Type::OBJECT)
    val = self.head.ludicrous_compile(function, env)
    function.if(function.rb_const_defined_from(val, self.mid)) {
      result.store(function.const(JIT::Type::OBJECT, "constant"))
    } .else {
      result.store(function.const(JIT::Type::OBJECT, false))
    } .end
    return result
  end
end

class CVAR
  def ludicrous_compile(function, env)
    set_source(function)
    return function.rb_cvar_get(env.cbase, self.vid)
  end

  def ludicrous_defined(function, env)
    result = function.value(JIT::Type::OBJECT)
    function.if(function.rb_cvar_defined(env.cbase, self.vid)) {
      result.store(function.const(JIT::Type::OBJECT, "class variable"))
    } .else {
      result.store(function.const(JIT::Type::OBJECT, false))
    } .end
    return result
  end
end

class CVASGN
  def ludicrous_compile(function, env)
    set_source(function)
    value = self.value.ludicrous_compile(function, env)
    return function.rb_cvar_set(env.cbase, self.vid, value)
  end
end

class GASGN
  def ludicrous_compile(function, env)
    set_source(function)
    name = function.rb_id2name(self.vid)
    value = self.value.ludicrous_compile(function, env)
    # TODO Use gvar_set (faster)
    return function.rb_gv_set(name, value)
  end
end

class GVAR
  def ludicrous_compile(function, env)
    set_source(function)
    name = function.rb_id2name(self.vid)
    # TODO Use gvar_get (faster)
    return function.rb_gv_get(name)
  end

  def ludicrous_defined(function, env)
    # TODO: The global entry is already stored in the node..
    global_entry = function.rb_global_entry(self.vid)
    result = function.value(JIT::Type::OBJECT)
    function.if(function.rb_gvar_defined(global_entry)) {
      result.store(function.const(JIT::Type::OBJECT, "global-variable"))
    } .else {
      result.store(function.const(JIT::Type::OBJECT, false))
    } .end
    return result
  end
end

class LIT
  def ludicrous_compile(function, env)
    return function.const(JIT::Type::OBJECT, self.lit)
  end
end

class RETURN
  def ludicrous_compile(function, env)
    if self.stts then
      retval = self.stts.ludicrous_compile(function, env)
    else
      retval = function.const(JIT::Type::OBJECT, nil)
    end
    env.return(retval)
    retval.is_returned = true
    return retval
  end
end

class NEWLINE
  def ludicrous_compile(function, env)
    # TODO: This might not be quite right.  Basically, any time that
    # ruby_set_current_source is called, it gets the line number from
    # the node currently being evaluated.  Of course, since we aren't
    # evaluating nodes, that information will be stale.  There are a
    # number of places in eval.c where ruby_set_current_source is
    # called; we need to evaluate a dummy node for each of those
    # cases.
    # TODO: This breaks tracing, since we don't try to call the the
    # trace func.
    # TODO: We might be able to optimize this by keeping a mapping of
    # instruction offset to source line and only modifying
    # ruby_sourceline when an exception is raised (or other event that
    # reads ruby_sourceline).
    env.file = self.nd_file
    env.line = self.nd_line
    return self.next.ludicrous_compile(function, env)
  end
end

class BLOCK
  def ludicrous_compile(function, env)
    set_source(function)
    n = self
    while n do
      last = n.head.ludicrous_compile(function, env)
      n = n.next
    end
    return last
  end
end

class SCOPE
  def ludicrous_compile(function, env)
    case self.next
    when nil
    when Node::ARGS, Node::BLOCK_ARG then function.const(JIT::Type::OBJECT, nil)
    else self.next.ludicrous_compile(function, env)
    end
  end
end

class SCLASS
  def ludicrous_compile(function, env)
    # TODO: Don't know how to implement this, so the singleton class
    # just gets eval'd instead of JIT compiled
    return function.rb_funcall(self, :eval, env.scope.self)
  end
end

class CLASS
  def ludicrous_compile(function, env)
    # TODO: Don't know how to implement this, so the class
    # just gets eval'd instead of JIT compiled
    return function.rb_funcall(self, :eval, env.scope.self)
  end
end

class MODULE
  def ludicrous_compile(function, env)
    # TODO: Don't know how to implement this, so the class
    # just gets eval'd instead of JIT compiled
    return function.rb_funcall(self, :eval, env.scope.self)
  end
end

class DEFS
  def ludicrous_compile(function, env)
    if self.defn then
      recv = self.recv.ludicrous_compile(function, env)
      klass = function.rb_singleton_class(recv)
      defn = function.const(JIT::Type::OBJECT, self.defn)
      set_source(function)
      function.rb_add_method(
          klass,
          function.const(JIT::Type::ID, self.mid),
          function.unwrap_node(defn),
          function.const(JIT::Type::INT, 0)) # TODO: noex
    end
    return function.const(JIT::Type::OBJECT, nil)
  end
end

class DEFN
  def ludicrous_compile(function, env)
    if self.defn then
      klass = function.rb_class_of(env.scope.self)
      defn = function.const(JIT::Type::OBJECT, self.defn)
      set_source(function)
      function.rb_add_method(
          klass,
          function.const(JIT::Type::ID, self.mid),
          function.unwrap_node(defn),
          function.const(JIT::Type::INT, 0)) # TODO: noex
    end
    return function.const(JIT::Type::OBJECT, nil)
  end
end

class ARGS
  def ludicrous_compile(function, env)
  end
end

class BLOCK_ARG
  def ludicrous_compile(function, env)
  end
end

class UNTIL
  def ludicrous_compile(function, env)
    cond = proc { self.cond.ludicrous_compile(function, env).rtest }
    retval = function.value(JIT::Type::OBJECT)
    function.until(cond).do { |loop|
      env.loop(loop) {
        if self.body then
          retval.store(self.body.ludicrous_compile(function, env))
        else
          retval.store(function.const(JIT::Type::OBJECT, nil))
        end
      }
    } .end
    return retval
  end
end

class WHILE
  def ludicrous_compile(function, env)
    cond = proc { self.cond.ludicrous_compile(function, env).rtest }
    retval = function.value(JIT::Type::OBJECT)
    function.while(cond).do { |loop|
      env.loop(loop) {
        if self.body then
          retval.store(self.body.ludicrous_compile(function, env))
        else
          retval.store(function.const(JIT::Type::OBJECT, nil))
        end
      }
    } .end
    return retval
  end
end

class YIELD
  def ludicrous_compile(function, env)
    if self.head then
      value = self.head.ludicrous_compile(function, env)
    else
      value = function.const(JIT::Type::OBJECT, [])
    end
    set_source(function)
    if self.state != 0 or not self.head then
      return function.rb_yield_splat(value)
    else
      return function.rb_yield(value)
    end
  end

  def ludicrous_defined(function, env)
    result = function.value(JIT::Type::OBJECT)
    function.if(function.rb_block_given_p()) {
      result.store(function.const(JIT::Type::OBJECT, "yield"))
    } .else {
      result.store(function.const(JIT::Type::OBJECT, false))
    } .end
    return result
  end
end

# The fastest way to iterate, but not 100% correct, because:
#   yield *[[1, 2]]
# should be yielded to us as:
#   [1, 2]
# but instead is yielded as:
#   [[1, 2]]
def ludicrous_iterate_fast(function, env, lhs, body, recv=nil, &block)
  # lhs - an assignment node that gets executed each time through
  # the loop
  # body - the body of the loop
  # recv -
  # 1. compile a nested function from the body of the loop
  # 2. pass this nested function as a parameter to 

  # scope_ptr = env.scope.address()
  scope_obj = env.scope.scope_obj

  iter_signature = JIT::Type.create_signature(
    JIT::ABI::CDECL,
    JIT::Type::OBJECT,
    [ JIT::Type::VOID_PTR ])
  iter_f = JIT::Function.compile(function.context, iter_signature) do |f|
    f.optimization_level = env.options.optimization_level

    iter_arg = Ludicrous::ITER_ARG_TYPE.wrap(f.get_param(0))
    outer_scope_obj = iter_arg.scope
    inner_recv = iter_arg.recv
    inner_scope = Ludicrous::AddressableScope.load(
        f, outer_scope_obj, env.scope.local_names, env.scope.args, env.scope.rest_arg)
    inner_env = Ludicrous::Environment.new(
        f, env.options, env.cbase, inner_scope)

    result = yield(f, inner_env, inner_recv)
    f.insn_return(result)
  end

  body_signature = JIT::Type::create_signature(
    JIT::ABI::CDECL,
    JIT::Type::OBJECT,
    [ JIT::Type::OBJECT, JIT::Type::VOID_PTR ])
  body_f = JIT::Function.compile(function.context, body_signature) do |f|
    f.optimization_level = env.options.optimization_level

    value = f.get_param(0)
    outer_scope_obj = f.get_param(1)
    inner_scope = Ludicrous::AddressableScope.load(
        f, outer_scope_obj, env.scope.local_names, env.scope.args, env.scope.rest_arg)
    inner_env = Ludicrous::Environment.new(
        f, env.options, env.cbase, inner_scope)

    r = inner_env.iter { |loop|
      ludicrous_assign(f, inner_env, lhs, value)

      if body then
        body.set_source(f)
        result = body.ludicrous_compile(f, inner_env)
      else
        result = f.const(JIT::Type::OBJECT, nil)
      end
      result
    }

    f.insn_return(r)
    # puts f
  end

  iter_arg = Ludicrous::ITER_ARG_TYPE.create(function)
  iter_arg.recv = recv ? recv : function.const(JIT::Type::OBJECT, nil)
  iter_arg.scope = scope_obj

  # TODO: will this leak memory if the function is redefined later?
  iter_c = function.const(JIT::Type::FUNCTION_PTR, iter_f.to_closure)
  body_c = function.const(JIT::Type::FUNCTION_PTR, body_f.to_closure)
  set_source(function)
  return function.rb_iterate(iter_c, iter_arg.ptr, body_c, scope_obj)
end

# The next fastest way to iterate, using avalue instead of svalue (so it
# may be faster for yield splat)
def ludicrous_iter_proc(function, env, lhs, body)
  scope_obj = env.scope.scope_obj

  body_signature = JIT::Type::create_signature(
    JIT::ABI::CDECL,
    JIT::Type::OBJECT,
    [ JIT::Type::OBJECT, JIT::Type::VOID_PTR ])
  body_f = JIT::Function.compile(function.context, body_signature) do |f|
    f.optimization_level = env.options.optimization_level

    value = f.get_param(0)
    outer_scope_obj = f.get_param(1)
    inner_scope = Ludicrous::AddressableScope.load(
        f, outer_scope_obj, env.scope.local_names, env.scope.args, env.scope.rest_arg)
    inner_env = Ludicrous::Environment.new(
        f, env.options, env.cbase, inner_scope)

    if not (MASGN === lhs) then
      value = value.avalue_splat
    end

    r = inner_env.iter { |loop|
      ludicrous_assign(f, inner_env, lhs, value)

      if body then
        body.set_source(f)
        result = body.ludicrous_compile(f, inner_env)
      else
        result = f.const(JIT::Type::OBJECT, nil)
      end
      result
    }

    f.insn_return(r)
    # puts f
  end

  # TODO: will this leak memory if the function is redefined later?
  body_c = function.const(JIT::Type::FUNCTION_PTR, body_f.to_closure)
  set_source(function)
  return function.rb_proc_new(body_c, scope_obj)
end

# The slowest way to iterate, but matches ruby's behavior 100%
def ludicrous_iter_splat_proc(function, env, lhs, body)
  scope_obj = env.scope.scope_obj

  body_signature = JIT::Type::create_signature(
    JIT::ABI::CDECL,
    JIT::Type::OBJECT,
    [ JIT::Type::OBJECT, JIT::Type::VOID_PTR ])
  body_f = JIT::Function.compile(function.context, body_signature) do |f|
    f.optimization_level = env.options.optimization_level

    ruby_scope = f.ruby_scope()
    local_vars_type = JIT::Array.new(JIT::Type::OBJECT, 4)
    local_vars = local_vars_type.wrap(
        f.ruby_struct_member(:SCOPE, :local_vars, ruby_scope))

    value = local_vars[2]

    outer_scope_obj = f.get_param(1)
    inner_scope = Ludicrous::AddressableScope.load(
        f, outer_scope_obj, env.scope.local_names, env.scope.args, env.scope.rest_arg)
    inner_env = Ludicrous::Environment.new(
        f, env.options, env.cbase, inner_scope)

    r = inner_env.iter { |loop|
      ludicrous_assign(f, inner_env, lhs, value.avalue_splat)

      if body then
        body.set_source(f)
        result = body.ludicrous_compile(f, inner_env)
      else
        result = f.const(JIT::Type::OBJECT, nil)
      end
      result
    }

    f.insn_return(r)
    # puts f
  end

  # TODO: will this leak memory if the function is redefined later?
  body_c = function.const(JIT::Type::FUNCTION_PTR, body_f.to_closure)
  set_source(function)
  return function.ludicrous_splat_iterate_proc(body_c, scope_obj)
end

def ludicrous_iterate_with_proc(function, env, recv, mid, args, is_fcall, block)
  case args
  when Node
    args = args.ludicrous_compile(function, env)
  when nil, false
    args = function.const(JIT::Type::OBJECT, [])
  else
    raise "Invalid value for args: #{args.inspect}"
  end

  if is_fcall then
    result = function.block_pass_fcall(recv, mid, args, block)
  else
    result = function.block_pass_call(recv, mid, args, block)
  end

  return result
end

def ludicrous_range_iterate(function, env, range_begin, range_end, var, body)
  result = function.value(JIT::Type::OBJECT)
  result.store(function.const(JIT::Type::OBJECT, nil))

  value = function.value(JIT::Type::OBJECT)
  value.store(range_begin)

  at_end = proc { ludicrous_compile_call(function, env, value, :==, [range_end]) }
  function.until(at_end).do { |loop|
    ludicrous_assign(function, env, var, value)
    loop.redo_from_here
    env.loop(loop) {
      if body then
        result.store(body.ludicrous_compile(function, env))
      end
      value.store(ludicrous_compile_call(function, env, value, :succ, []))
      result
    }
  } .end

  return result
end

def ludicrous_node_is_range(function, env, node)
  if DOT3 === node or DOT2 === node or (LIT === node and Range === node.lit) then
    case node
    when DOT3
      range_begin = node.beg.ludicrous_compile(function, env)
      range_end = node.end.ludicrous_compile(function, env)
    when DOT2
      range_begin = node.beg.ludicrous_compile(function, env)
      range_end = node.end.ludicrous_compile(function, env)
      range_end = ludicrous_compile_call(function, env, range_end, :succ, [])
    when LIT
      lit = function.const(JIT::Type::OBJECT, node.lit)
      range_begin = function.rb_ivar_get(lit, :begin)
      range_end = function.value(JIT::Type::OBJECT)
      range_end.store(function.rb_ivar_get(lit, :end))
      excl = function.rb_ivar_get(lit, function.const(JIT::Type::ID, :excl))
      function.unless(excl) {
        range_end.store(ludicrous_compile_call(function, env, range_end, :succ, []))
      } .end
    end

    return true, range_begin, range_end
  end

  return false
end

def ludicrous_array_iterate(function, env, array, var, body)
  result = function.value(JIT::Type::OBJECT)

  len = function.ruby_struct_member(:RArray, :len, array)
  ptr = function.ruby_struct_member(:RArray, :ptr, array)

  idx = function.value(JIT::Type::INT)
  idx.store(function.const(JIT::Type::INT, 0))

  function.until { idx == len }.do { |loop|
    env.loop(loop) {
      value = function.insn_load_elem(ptr, idx, JIT::Type::OBJECT)
      ludicrous_assign(function, env, var, value)
      if body then
        result.store(body.ludicrous_compile(function, env))
      end
      idx.store(idx + function.const(JIT::Type::INT, 1))
      result
    }
  } .end

  return result
end

class FOR
  LIBJIT_NEEDS_ADDRESSABLE_SCOPE = true

  def ludicrous_compile(function, env)
    # var - an assignment node that gets executed each time through
    # the loop
    # body - the body of the loop
    # iter - the sequence to iterate over
    # 1. compile a nested function from the body of the loop
    # 2. pass this nested function as a parameter to 

    is_range, range_begin, range_end = ludicrous_node_is_range(function, env, self.iter)
    if is_range then
      # We can optimize this into a loop (as long as Range#each isn't
      # overridden -- TODO)

      return ludicrous_range_iterate(function, env, range_begin, range_end, self.var, self.body)
    end

    result = function.value(JIT::Type::OBJECT)
    recv = self.iter.ludicrous_compile(function, env)

    done_label = JIT::Label.new

    # TODO: Don't do this if Array#each is redefined
    function.if(recv.is_type(Ludicrous::T_ARRAY)) {
      result.store(ludicrous_array_iterate(function, env, recv, self.var, self.body))
      function.insn_branch(done_label)
    } .end

    iterate_style = env.options.iterate_style || :splat

    case iterate_style
    when :fast
      v = ludicrous_iterate_fast(function, env, self.var, self.body, recv) do |f, inner_env, recv|
        self.iter.set_source(f)
        f.rb_funcall(recv, :each)
      end
      result.store(v)
    when :proc
      block = ludicrous_iter_proc(function, env, self.var, self.body)
      args = nil
      result = ludicrous_iterate_with_proc(
          function, env, recv, :each, args, false, block)
    when :splat
      block = ludicrous_iter_splat_proc(function, env, self.var, self.body)
      args = nil
      result = ludicrous_iterate_with_proc(
          function, env, recv, :each, args, false, block)
    else
      raise "Invalid iterate style #{iterate_style}"
    end

    function.insn_label(done_label)

    return result
  end
end

class NEXT
  def ludicrous_compile(function, env)
    if self.stts then
      # rb_iter_break doesn't take an argument
      raise "Can't use an argument with NEXT"
    else
      env.next
    end

    # Won't ever return, but this makes next if... happy
    return function.const(JIT::Type::OBJECT, nil)
  end
end

class REDO
  def ludicrous_compile(function, env)
    env.redo

    # Won't ever return, but this makes redo if... happy
    return function.const(JIT::Type::OBJECT, nil)
  end
end

class BREAK
  def ludicrous_compile(function, env)
    if self.stts then
      # rb_iter_break doesn't take an argument
      raise "Can't use an argument with BREAK"
    else
      set_source(function)
      env.break
    end

    # Won't ever return, but this makes break if... happy
    return function.const(JIT::Type::OBJECT, nil)
  end
end

class ITER
  LIBJIT_NEEDS_ADDRESSABLE_SCOPE = true

  def ludicrous_compile(function, env)
    # var - an assignment node that gets executed each time through
    # the loop
    # body - the body of the loop
    # iter - the sequence to iterate over
    # 1. compile a nested function from the body of the loop
    # 2. pass this nested function as a parameter to 

    if env.options.iterate_style then
      iterate_style = env.options.iterate_style
    else
      if self.var then
        iterate_style = :splat
      else
        # Okay to iterate fast style if the block takes no arguments
        iterate_style = :fast
      end
    end

    # TODO: I think ITER is supposed to get its own scope?
    case iterate_style
    when :fast
      result = ludicrous_iterate_fast(
          function, env, self.var, self.body) do |f, inner_env, recv|
        self.iter.set_source(f)
        self.iter.ludicrous_compile(f, inner_env)
      end
    when :proc
      block = ludicrous_iter_proc(function, env, self.var, self.body)
      case self.iter
      when Node::CALL
        recv = self.iter.recv.ludicrous_compile(function, env)
        mid = self.iter.mid
        args = self.iter.args
        result = ludicrous_iterate_with_proc(
            function, env, recv, mid, args, false, block)
      when Node::FCALL
        recv = env.scope.self
        mid = self.iter.mid
        args = self.iter.args
        result = ludicrous_iterate_with_proc(
            function, env, recv, mid, args, true, block)
      else
        raise "Cannot iterate with #{self.iter}"
      end
    when :splat
      block = ludicrous_iter_splat_proc(function, env, self.var, self.body)
      case self.iter
      when Node::CALL
        recv = self.iter.recv.ludicrous_compile(function, env)
        mid = self.iter.mid
        args = self.iter.args
        result = ludicrous_iterate_with_proc(
            function, env, recv, mid, args, false, block)
      when Node::FCALL
        recv = env.scope.self
        mid = self.iter.mid
        args = self.iter.args
        result = ludicrous_iterate_with_proc(
            function, env, recv, mid, args, true, block)
      else
        raise "Cannot iterate with #{self.iter}"
      end
    else
      raise "Invalid iterate style #{iterate_style}"
    end

    return result
  end
end

class Node::BEGIN
  def ludicrous_compile(function, env)
    return self.body.ludicrous_compile(function, env)
  end
end

class ENSURE
  LIBJIT_NEEDS_ADDRESSABLE_SCOPE = true

  def ludicrous_compile(function, env)
    scope_obj = env.scope.scope_obj()

    body_signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::VOID_PTR ])
    body_f = JIT::Function.compile(function.context, body_signature) do |f|
      f.optimization_level = env.options.optimization_level

      outer_scope_obj = f.get_param(0)
      inner_scope = Ludicrous::AddressableScope.load(f, outer_scope_obj, env.scope.local_names, env.scope.args, env.scope.rest_arg)
      inner_env = Ludicrous::Environment.new(
          f, env.options, env.cbase, inner_scope)

      result = self.head.ludicrous_compile(f, inner_env)
      f.insn_return(result)
    end

    ensr_signature = JIT::Type::create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT, JIT::Type::VOID_PTR ])
    ensr_f = JIT::Function.compile(function.context, ensr_signature) do |f|
      f.optimization_level = env.options.optimization_level

      outer_scope_obj = f.get_param(0)
      inner_scope = Ludicrous::AddressableScope.load(f, outer_scope_obj, env.scope.local_names, env.scope.args, env.scope.rest_arg)
      inner_env = Ludicrous::Environment.from_outer(f, inner_scope, env)

      result = self.ensr.ludicrous_compile(f, inner_env)
      f.insn_return(result)
    end

    # TODO: will this leak memory if the function is redefined later?
    body_c = function.const(JIT::Type::FUNCTION_PTR, body_f.to_closure)
    ensr_c = function.const(JIT::Type::FUNCTION_PTR, ensr_f.to_closure)
    set_source(function)
    result = function.rb_ensure(body_c, scope_obj, ensr_c, scope_obj)
    return result
  end
end

class RESCUE
  LIBJIT_NEEDS_ADDRESSABLE_SCOPE = true

  def ludicrous_compile(function, env)
    scope_obj = env.scope.scope_obj()

    body_signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::VOID_PTR ])
    body_f = JIT::Function.compile(function.context, body_signature) do |f|
      f.optimization_level = env.options.optimization_level

      outer_scope_obj = f.get_param(0)
      inner_scope = Ludicrous::AddressableScope.load(f, outer_scope_obj, env.scope.local_names, env.scope.args, env.scope.rest_arg)
      inner_env = Ludicrous::Environment.from_outer(f, inner_scope, env)

      result = self.head.ludicrous_compile(f, inner_env)
      f.insn_return(result)
    end
 
    # TODO: will this leak memory if the function is redefined later?
    body_c = function.const(JIT::Type::FUNCTION_PTR, body_f.to_closure)
    set_source(function)
    state = function.value(JIT::Type::INT)
    state.store(function.const(JIT::Type::INT, 0))
    result = function.value(JIT::Type::OBJECT)
    result.store(function.const(JIT::Type::OBJECT, nil))
    result.store(function.rb_protect(body_c, scope_obj, state.address))

    return_label = JIT::Label.new
    no_exception_label = JIT::Label.new
    is_return = (state == function.const(JIT::Type::INT, 0))
    function.insn_branch_if(is_return, return_label)
    is_exception = (state == function.const(JIT::Type::INT, Ludicrous::TAG_RAISE))

    function.if(is_exception) {
      resq = self.resq
      ruby_errinfo = function.ruby_errinfo()
      while resq do
        handle_rescue = handle_rescue(function, env, resq, ruby_errinfo)
        function.if(handle_rescue) {
          if resq.body then
            result.store(resq.body.ludicrous_compile(function, env))
          end
        } .end
        function.insn_branch(return_label)
        resq = resq.head
      end
    } .end

    # TODO: need to call set_source here?
    function.rb_jump_tag(state)
    function.insn_label(return_label)

    if self.else then
      raise "Can't handle else clause on a RESCUE"
    end

    return result
  end

  def handle_rescue(function, env, resq, ruby_errinfo)
    if not resq.args then
      types = [ function.const(JIT::Type::OBJECT, StandardError) ]
    else
      types = resq.args.to_a.map { |n| n.ludicrous_compile(function, env) }
    end

    result = function.value(JIT::Type::UINT)
    result.store(function.const(JIT::Type::OBJECT, false))
    resq.set_source(function)
    types.each do |type|
      result = result | function.rb_funcall(type, :===, ruby_errinfo)
    end
    return result
  end
end

=begin
TODO: we can't blindly use rb_jump_tag here, because our rescue clause
isn't inside an rb_protect.  That's easy enough to fix, but retry also
works inside a loop, in which case we may need to jump to the beginning
of the loop if the loop is inlined.
class RETRY
  def ludicrous_compile(function, env)
    function.rb_jump_tag(function.const(JIT::Type::INT, Ludicrous::TAG_RETRY))
  end
end
=end

=begin
TODO: break should be a local jump to the end of the loop (but we can't
do a local jump unless the loop is inlined, so this isn't an easy node
to implement).
class BREAK
  def ludicrous_compile(function, env)
    function.rb_jump_tag(function.const(JIT::Type::INT, Ludicrous::TAG_BREAK))
  end
end
=end

class IF
  def ludicrous_compile(function, env)
    cond = self.cond.ludicrous_compile(function, env).rtest
    result = function.value(JIT::Type::OBJECT)
    function.if(cond) {
      if self.body then
        result.store(self.body.ludicrous_compile(function, env))
      end
    } .else {
      if self.else then
        # there might be a return inside the else, in which case we
        # don't want to store the result (which wouldn't work)
        else_result = self.else.ludicrous_compile(function, env)
        result.store(else_result) if else_result
      end
    } .end
    return result
  end
end

def ludicrous_compile_when(function, env, n, &match)
  done_label = JIT::Label.new

  result = function.value(JIT::Type::OBJECT)
  result.store(function.const(JIT::Type::OBJECT, nil))

  while WHEN === n do
    next_label = JIT::Label.new
    match_label = JIT::Label.new
    to_match_list = n.head.to_a
    for to_match in to_match_list do
      m = to_match.ludicrous_compile(function, env)
      to_match.set_source(function)
      cond = match.call(m)
      function.insn_branch_if(cond, match_label)
    end
    function.insn_branch(next_label)
    function.insn_label(match_label)
    if n.body then
      result.store(n.body.ludicrous_compile(function, env))
    else
      result.store(function.const(JIT::Type::OBJECT, nil))
    end
    function.insn_branch(done_label)
    function.insn_label(next_label)
    n = n.next
  end

  if n then
    # else
    result.store(n.ludicrous_compile(function, env))
  end

  function.insn_label(done_label)
  if self.next then
    # a statement comes after the case/when sequence
    result.store(n.ludicrous_compile(function, env))
  end

  return result
end

# case <xxx>
# when <yyy>
# when <zzz>
# end
#
# means check yyy === xxx then zzz === xxx
#
# TODO: CASE has a next member; how do we get there from here?
class CASE
  def ludicrous_compile(function, env)
    value = self.head.ludicrous_compile(function, env)

    return ludicrous_compile_when(function, env, self.body) do |m|
      function.rb_funcall(m, :===, value).rtest
    end
  end
end

# case
# when yyy
# when when zzz
#
# means check rtest(yyy) then rtest(zzz)
class WHEN
  def ludicrous_compile(function, env)
    return ludicrous_compile_when(function, env, self.body) do |m|
      m.rtest
    end
  end
end

class NOT
  def ludicrous_compile(function, env)
    return self.body.ludicrous_compile(function, env).rnot
  end
end

class OR
  def ludicrous_compile(function, env)
    result = function.value(JIT::Type::OBJECT)
    result.store(self.first.ludicrous_compile(function, env))
    function.unless(result.rtest) {
      result.store(self.second.ludicrous_compile(function, env))
    } .end
    return result
  end
end

class AND
  def ludicrous_compile(function, env)
    result = function.value(JIT::Type::OBJECT)
    result.store(self.first.ludicrous_compile(function, env))
    function.if(result.rtest) {
      result.store(self.second.ludicrous_compile(function, env))
    } .end
    return result
  end
end

class STR
  def ludicrous_compile(function, env)
    str = function.const(JIT::Type::OBJECT, self.lit)
    return function.rb_str_dup(str)
  end
end

class DSTR
  def ludicrous_compile(function, env)
    set_source(function)
    str = function.rb_str_dup(self.lit)
    a = self.next.to_a
    a.each do |elem|
      v = elem.ludicrous_compile(function, env)
      s = function.rb_funcall(v, :to_s)
      function.rb_str_concat(str, s)
    end
    return str
  end
end

class XSTR
  def ludicrous_compile(function, env)
    id_backtick = function.const(JIT::Type::UINT, ?`)
    lit = function.const(JIT::Type::OBJECT, self.lit)
    return function.rb_funcall(env.scope.self, id_backtick, lit)
  end
end

class DXSTR
  def ludicrous_compile(function, env)
    set_source(function)
    str = function.rb_str_dup(self.lit)
    a = self.next.to_a
    a.each do |elem|
      v = elem.ludicrous_compile(function, env)
      s = function.rb_funcall(v, :to_s)
      function.rb_str_concat(str, s)
    end
    id_backtick = function.const(JIT::Type::UINT, ?`)
    return function.rb_funcall(env.scope.self, id_backtick, str)
  end
end

class EVSTR
  def ludicrous_compile(function, env)
    return self.body.ludicrous_compile(function, env)
  end
end

class ARRAY
  def ludicrous_compile(function, env)
    a = self.to_a
    set_source(function)
    ary = function.rb_ary_new2(a.length)
    a.each_with_index do |elem, idx|
      value = elem.ludicrous_compile(function, env)
      function.rb_ary_store(ary, idx, value)
    end
    return ary
  end
end

class ZARRAY
  def ludicrous_compile(function, env)
    set_source(function)
    return function.rb_ary_new2(0)
  end
end

class TO_ARY
  def ludicrous_compile(function, env)
    lit = self.head.ludicrous_compile(function, env)
    return function.rb_ary_to_ary(lit)
  end
end

class HASH
  def ludicrous_compile(function, env)
    set_source(function)
    hash = function.rb_hash_new()
    a = self.head
    while a do
      k = a.head.ludicrous_compile(function, env)
      a = a.next
      v = a.head.ludicrous_compile(function, env)
      function.rb_hash_aset(hash, k, v)
      a = a.next
    end
    return hash
  end
end

def ludicrous_create_range(function, env, begin_node, end_node, exclude_end)
  range_begin = self.beg.ludicrous_compile(function, env)
  range_end = self.end.ludicrous_compile(function, env)
  set_source(function)
  return function.rb_range_new(range_begin, range_end, exclude_end ? 1 : 0)
end

class DOT2
  def ludicrous_compile(function, env)
    return ludicrous_create_range(function, env, self.beg, self.end, false)
  end
end

class DOT3
  def ludicrous_compile(function, env)
    return ludicrous_create_range(function, env, self.beg, self.end, true)
  end
end

class SPLAT
  def ludicrous_compile(function, env)
    value = self.head.ludicrous_compile(function, env)
    return value.splat
  end
end

class SVALUE
  def ludicrous_compile(function, env)
    avalue = self.head.ludicrous_compile(function, env)
    return avalue.avalue_splat
  end
end

class ARGSCAT
  def ludicrous_compile(function, env)
    args = self.head.ludicrous_compile(function, env)
    splat = self.body.ludicrous_compile(function, env).splat
    return function.rb_ary_concat(args, splat)
  end
end

class NTH_REF
  def ludicrous_compile(function, env)
    # cnt = function.const(JIT::Type::INT, self.cnt)
    # p_match_data = function.rb_svar(cnt)
    # match_data = function.insn_load_relative(p_match_data, 0, JIT::Type::OBJECT)
    # nth = function.const(JIT::Type::INT, self.nth)
    # return function.rb_reg_nth_match(nth, match_data)

    # TODO: We can't supported $1..$9 inside a block, so for now it's
    # disabled altogether
    raise "$#{self.cnt} not supported"
  end
end

class MATCH
  def ludicrous_compile(function, env)
    lit = function.const(JIT::Type::OBJECT, self.lit)
    return function.rb_reg_match2(lit)
  end
end

class MATCH2
  def ludicrous_compile(function, env)
    recv = self.recv.ludicrous_compile(function, env)
    value = self.value.ludicrous_compile(function, env)
    return function.rb_reg_match(recv, value)
  end
end

class MATCH3
  def ludicrous_compile(function, env)
    recv = self.recv.ludicrous_compile(function, env)
    value = self.value.ludicrous_compile(function, env)
    result = function.value(JIT::Type::OBJECT)
    set_source(function)
    function.if(recv.is_type(Ludicrous::T_STRING)) {
      result.store(function.rb_reg_match(recv, value))
    } .else {
      result.store(function.rb_funcall(value, :=~, recv))
    } .end
    return result
  end
end

end # class Node

