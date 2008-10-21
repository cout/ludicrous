module Ludicrous

class ScopeBase
  attr_reader :args
  attr_reader :rest_arg

  def initialize(function, local_names, locals, args = [], rest_arg = nil)
    @function = function
    @self = Ludicrous::LocalVariable.new(@function, "SELF")

    @local_names = local_names
    @locals = locals

    @args = args
    @rest_arg = rest_arg
  end

  def local_set(vid, value)
    local = @locals[vid]
    if not local then
      raise "Cannot set #{vid}: no such local variable defined"
    end
    local.set(value)
    return value
  end

  def local_get(vid)
    local = @locals[vid]
    if not local then
      raise "Cannot get #{vid}: no such local variable defined"
    end
    return local.get()
  end

  def local_defined(vid)
    return @locals[vid] != nil
  end

  def self
    return @self.get
  end

  def self=(value)
    @self.set(value)
  end

  def arg_set(vid, value)
    local_set(vid, value)
    @args << vid
  end

  def rest_arg_set(vid, value)
    local_set(vid, value)
    @rest_arg = vid
  end

  def argv
    argv = @function.rb_ary_new2(@args.size)
    @args.each_with_index do |vid, idx|
      @function.rb_ary_store(argv, idx, local_get(vid))
    end
    if @rest_arg then
      @function.rb_ary_concat(argv, local_get(@rest_arg))
    end
    return argv
  end
end

class Scope < ScopeBase
  def initialize(function, local_names, args = [], rest_arg = nil)
    locals = {}
    local_names.each do |name|
      locals[name] = Ludicrous::LocalVariable.new(function, name)
      locals[name].init()
    end

    super(function, local_names, locals, args, rest_arg)
  end
end

class AddressableScope < ScopeBase
  attr_reader :local_names
  attr_reader :scope_obj

  def self.scope_type(local_names)
    return JIT::Struct.new(
        [ :len      , JIT::Type::UINT   ],
        [ :dynavars , JIT::Type::OBJECT ],
        [ :self     , JIT::Type::OBJECT ],
        *local_names.map { |name| [ name, JIT::Type::OBJECT ] }
    )
  end

  JIT::Context.build do |context|
    signature = JIT::Type.create_signature(
        JIT::ABI::CDECL,
        JIT::Type::VOID,
        [ JIT::Type::VOID_PTR ])
    MARK_FUNCTION = JIT::Function.compile(context, signature) do |f|
      scope_ptr = f.get_param(0)
      scope_size = f.insn_load_relative(scope_ptr, 0, JIT::Type::UINT)
      start_ptr = scope_ptr + f.const(JIT::Type::UINT, 4) # TODO: not 64-bit safe
      end_ptr = scope_ptr + scope_size
      f.if(start_ptr < end_ptr) {
        f.rb_gc_mark_locations(start_ptr, end_ptr)
      } .end
      f.insn_return()
    end
  end

  MARK_CLOSURE = MARK_FUNCTION.to_closure


=begin
  JIT::Context.build do |context|
    signature = JIT::Type.create_signature(
        JIT::ABI::CDECL,
        JIT::Type::VOID,
        [ JIT::Type::VOID_PTR ])
    FREE_FUNCTION = JIT::Function.compile(context, signature) do |f|
      ptr = f.get_param(0)
      # f.debug_print_msg("Freeing scope")
      # f.debug_print_uint(ptr)
      f.ruby_xfree(ptr)
      f.insn_return()
    end
  end

  FREE_CLOSURE = FREE_FUNCTION.to_closure
=end

  # TODO: This function isn't right
  def self.load(function, scope_obj, local_names, args, rest_arg)
    scope_ptr = function.data_get_struct(scope_obj)
    scope_type = self.scope_type(local_names)
    locals = {}
    local_names.each_with_index do |name, idx|
      offset = scope_type.offset_of(name)
      locals[name] = Ludicrous::LocalVariable.load(function, name, scope_ptr, offset)
    end
    return self.new(function, local_names, locals, args, rest_arg, scope_ptr, scope_obj)
  end

  def initialize(function, local_names, locals=nil, args=[], rest_arg=nil, scope_ptr=nil, scope_obj=nil)
    need_init = false

    if not locals then
      locals = {}
      need_init = true
      local_names.each do |name|
        locals[name] = Ludicrous::LocalVariable.new(function, name)
      end
    end

    super(function, local_names, locals, args, rest_arg)

    scope_type = self.class.scope_type(local_names)
    scope_size = function.const(JIT::Type::UINT, scope_type.size)

    if not scope_ptr then
      scope_ptr = @function.ruby_xcalloc(1, scope_size)
    end

    @scope_ptr = scope_ptr

    @dynavars = Ludicrous::LocalVariable.new(@function, "DYNAVARS")
    @scope_size = Ludicrous::LocalVariable.new(@function, "SCOPE_SIZE")

    @scope_size.set_addressable(@scope_ptr, scope_type.get_offset(0))
    @dynavars.set_addressable(@scope_ptr, scope_type.get_offset(1))
    @self.set_addressable(@scope_ptr, scope_type.get_offset(2))

    @local_names.each_with_index do |name, idx|
      offset = scope_type.offset_of(name)
      @locals[name].set_addressable(@scope_ptr, offset) if @locals[name]
      @locals[name].init if need_init
    end

    if scope_obj then
      @scope_obj = scope_obj
    else
      @scope_obj = @function.data_wrap_struct(
          Ludicrous::Scope,
          MARK_CLOSURE,
          Ludicrous.function_pointer_of(:ruby_xfree),
          @scope_ptr)
      @scope_size.set(scope_size)

      # Creating the dynavars hash MUST happen last, otherwise the GC
      # might get invoked before the scope is setup
      @self.set(@function.const(JIT::Type::OBJECT, nil)) # TODO: might not be necessary
      @dynavars.set(@function.rb_hash_new())
    end
  end

  # TODO: a hash is easy to use, but maybe not very fast
  def dyn_set(vid, value)
    if local_defined(vid) then
      local_set(vid, value)
    else
      @function.rb_hash_aset(@dynavars.get, vid, value)
    end
  end

  def dyn_get(vid)
    if local_defined(vid) then
      return local_get(vid)
    else
      value = @function.rb_hash_aref(@dynavars.get, vid)
      return value
    end
  end

  def dyn_defined(vid)
    if local_defined(vid) then
      return @function.const(JIT::Type::OBJECT, true)
    else
      has_key = @function.rb_funcall(@dynavars.get, :has_key?, vid)
      return has_key # 0 will be false
    end
  end
end

end # Ludicrous

