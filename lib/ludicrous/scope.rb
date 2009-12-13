require 'ludicrous/local_variable'

module Ludicrous

# The base class for all scope objects.  The scope keeps track of the
# arguments and local variables for a given function or scope.  Blocks
# are given their own scope.  If a function has a block, it must use an
# AddressableScope, otherwise it can use a regular Scope.
class ScopeBase
  attr_reader :args
  attr_reader :rest_arg

  # Create a new scope.
  #
  # ScopeBase objects should not be directly instantiated; rather, a
  # derived instance should be created instead.
  #
  # +function+:: the JIT::Function currently being compiled
  # +local_names+:: an Array of Symbol containing the names of all the
  # local variables
  # +locals+:: a Hash mapping the name of each local variable as a
  # Symbol to the LocalVariable object for that variable
  # +args+:: an Array of Symbol containing the names of all the
  # arguments to the function
  # +rest_arg+:: a Symbol with the name of the rest arg (the argument in
  # the argument list preceded by the splat operator)
  def initialize(function, local_names, locals, args = [], rest_arg = nil)
    @function = function
    @self = Ludicrous::LocalVariable.new(@function, "SELF")

    @local_names = local_names
    @locals = locals

    @args = args
    @rest_arg = rest_arg
  end

  # Emit code to set a local variable
  #
  # +vid+:: a Symbol with the name of the variable to set
  # +value+:: a JIT::Value containing the new value of the variable
  def local_set(vid, value)
    local = @locals[vid]
    if not local then
      raise "Cannot set #{vid}: no such local variable defined"
    end
    local.set(value)
    return value
  end

  # Emit code to retrieve a local variable
  #
  # +vid+:: a Symbol with the name of the variable to get
  def local_get(vid)
    local = @locals[vid]
    if not local then
      raise "Cannot get #{vid}: no such local variable defined"
    end
    return local.get()
  end

  # Return true if the indicated local variable has been defined at this
  # point, false otherwise
  #
  # +vid+:: a Symbol with the name of the variable to test
  def local_defined(vid)
    return @locals[vid] != nil
  end

  # Get the object reference for the self variable.
  #
  # Returns a JIT::Value with the value of the self variable.
  def self
    return @self.get
  end

  # Sets the self variable.
  #
  # This method should be called once at the beginning of the
  # compilation of a function.
  #
  # +value+:: a JIT::Value containing the value of the variable
  def self=(value)
    @self.set(value)
  end

  # Sets the value of a method argument.
  #
  # This method should be called once at the beginning of the
  # compilation of a function.
  #
  # +vid+:: a Symbol with the name of the argument to set
  # +value+:: a JIT::Value containing the value of the argument
  def arg_set(vid, value)
    local_set(vid, value)
    @args << vid
  end

  # Sets the value of a method's rest argument.
  #
  # This method should be called once at the beginning of the
  # compilation of a function.
  #
  # +vid+:: a Symbol with the name of the argument to set
  # +value+:: a JIT::Value containing the value of the argument
  def rest_arg_set(vid, value)
    local_set(vid, value)
    @rest_arg = vid
  end

  # Emit code to build an array containing all the arguments to the
  # function.
  #
  # Returns an RArray containing the values of all the arguments to the
  # function.
  def argv
    ary = @function.rb_ary_new2(@args.size)
    argv = RArray.wrap(ary)
    @args.each_with_index do |vid, idx|
      argv[idx] = local_get(vid)
    end
    if @rest_arg then
      rest = RArray.wrap(local_get(@rest_arg))
      argv.concat(rest)
    end
    return argv
  end
end

# A non-addressable scope whose variables can only be accessed from
# inside the current scope.
class Scope < ScopeBase
  # Create a new Scope.
  #
  # +function+:: the JIT::Function currently being compiled
  # +local_names+:: an Array of Symbol containing the names of all the
  # local variables
  # +locals+:: a Hash mapping the name of each local variable as a
  # Symbol to the LocalVariable object for that variable
  # +args+:: an Array of Symbol containing the names of all the
  # arguments to the function
  # +rest_arg+:: a Symbol with the name of the rest arg (the argument in
  # the argument list preceded by the splat operator)
  def initialize(function, local_names, args = [], rest_arg = nil)
    locals = {}
    local_names.each do |name|
      locals[name] = Ludicrous::LocalVariable.new(function, name)
      locals[name].init()
    end

    super(function, local_names, locals, args, rest_arg)
  end
end

# A addressable scope for use when the local variables need to be
# accessed outside the current scope, e.g. when the method being
# compiled uses an iteration block.
class AddressableScope < ScopeBase
  # An Array of Symbol containing the names of all the local variables
  attr_reader :local_names

  # A JIT::Value referencing an Object for this scope, to be used with
  # +rb_iterate+.
  attr_reader :scope_obj

  # Return a JIT::Type for an underlying scope object with the given
  # local variables.
  #
  # This function should not normally be called by the user.
  #
  # +local_names+:: an Array of Symbol containing the names of all the
  # local variables in the scope.
  def self.scope_type(local_names)
    return JIT::Struct.new(
        [ :len      , JIT::Type::UINT   ],
        [ :dynavars , JIT::Type::OBJECT ],
        [ :self     , JIT::Type::OBJECT ],
        *local_names.map { |name| [ name, JIT::Type::OBJECT ] }
    )
  end

  # Create a JIT::Function to mark all the local variables in an addressable scope.
  #
  # Returns the new function
  def self.mark_function
    return JIT::Function.build([ :VOID_PTR ] => :VOID) do |f|
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

  ##
  # A JIT::Function to mark all the local variables in an addressable scope.
  MARK_FUNCTION = mark_function()

  ##
  # A C function to mark all the local variables in an addressable
  # scope.
  MARK_CLOSURE = MARK_FUNCTION.to_closure

  def self.free_function
    return JIT::Function.build([ :VOID_PTR ] => :VOID) do |f|
      ptr = f.get_param(0)
      f.ruby_xfree(ptr)
      f.insn_return()
    end
  end

  # FREE_FUNCTION = free_function()
  # FREE_CLOSURE = FREE_FUNCTION.to_closure
  FREE_CLOSURE = Ludicrous.function_pointer_of(:ruby_xfree),

  # Create a new inner scope from an outer scope, for use with
  # +rb_iterate+.
  #
  # +function+:: the inner JIT::Function being compiled
  # +scope_obj+:: an object reference to the underlying scope object (as
  # returned by #scope_obj in the outer scope)
  # +local_names+:: an Array of Symbol containing the names of all the
  # local variables
  # +args+:: an Array of Symbol containing the names of all the
  # arguments to the function
  # +rest_arg+:: a Symbol with the name of the rest arg (the argument in
  # the argument list preceded by the splat operator)
  def self.load(function, scope_obj, local_names, args, rest_arg)
    # TODO: This function isn't right
    scope_ptr = function.data_get_struct(scope_obj)
    scope_type = self.scope_type(local_names)
    locals = {}
    local_names.each_with_index do |name, idx|
      offset = scope_type.offset_of(name)
      locals[name] = Ludicrous::LocalVariable.load(function, name, scope_ptr, offset)
    end
    return self.new(function, local_names, locals, args, rest_arg, scope_ptr, scope_obj)
  end

  # Create a new AddressableScope.
  #
  # +function+:: the JIT::Function currently being compiled
  # +local_names+:: an Array of Symbol containing the names of all the
  # local variables
  # +locals+:: a Hash mapping the name of each local variable as a
  # Symbol to the LocalVariable object for that variable
  # +args+:: an Array of Symbol containing the names of all the
  # arguments to the function
  # +rest_arg+:: a Symbol with the name of the rest arg (the argument in
  # the argument list preceded by the splat operator)
  # +scope_ptr+:: a pointer to the underlying scope object
  # +scope_obj+:: an object reference to the underlying scope object (as
  # returned by #scope_obj in the outer scope)
  def initialize(function, local_names, locals=nil, args=[], rest_arg=nil, scope_ptr=nil, scope_obj=nil)
    # TODO: this is really two separate methods:
    # 1) if we are wrapping a scope
    # 2) if we are creating a new scope
    #
    # This duality makes this code VERY brittle.  BE CAREFUL!

    if locals then
      need_init = false
    else
      # TODO: Odd: to call a method before initializing the base class
      locals = create_locals(function, local_names)
      need_init = true
    end

    super(function, local_names, locals, args, rest_arg)

    scope_type = self.class.scope_type(local_names)
    scope_size = function.const(JIT::Type::UINT, scope_type.size)

    @scope_ptr = scope_ptr || @function.ruby_xcalloc(1, scope_size)

    # TODO: scope_size is NOT a normal object!
    @dynavars = Ludicrous::LocalVariable.new(@function, "DYNAVARS")
    @scope_size = Ludicrous::LocalVariable.new(@function, "SCOPE_SIZE")

    @scope_size.set_addressable(@scope_ptr, scope_type.get_offset(0))
    @dynavars.set_addressable(@scope_ptr, scope_type.get_offset(1))
    @self.set_addressable(@scope_ptr, scope_type.get_offset(2))

    init_locals(scope_type, need_init)
    @scope_obj = scope_obj || wrap_scope(scope_size)

    # Creating the dynavars hash MUST happen last, otherwise the GC
    # might get invoked before the scope is setup
    @self.set(@function.const(JIT::Type::OBJECT, nil)) # TODO: might not be necessary
    @dynavars.set(@function.rb_hash_new())
  end

  def create_locals(function, local_names)
    locals = {}
    local_names.each do |name|
      locals[name] = Ludicrous::LocalVariable.new(function, name)
    end
    return locals
  end

  def init_locals(scope_type, need_init)
    @local_names.each_with_index do |name, idx|
      offset = scope_type.offset_of(name)
      @locals[name].set_addressable(@scope_ptr, offset) if @locals[name]
      @locals[name].init if need_init
    end
  end

  def wrap_scope(scope_size)
    scope_obj = @function.data_wrap_struct(
        Ludicrous::Scope,
        MARK_CLOSURE,
        Ludicrous.function_pointer_of(:ruby_xfree),
        @scope_ptr)
    @scope_size.set(scope_size)
    return scope_obj
  end

  # Set a dynamic variable.
  #
  # A dynamic variable differs from a local variable in that it exists
  # only in an inner scope.
  #
  # If Ludicrous can determine the existence of a dynamic variable
  # statically, it will preallocate a slot for it in the local variable
  # table and access will be as fast as for local variables, otherwise
  # it will revert to a hash lookup.
  #
  # +vid+:: a Symbol with the name of the variable to set
  # +value+:: a JIT::Value containing the new value of the variable
  def dyn_set(vid, value)
    # TODO: a hash is easy to use, but maybe not very fast
    if local_defined(vid) then
      local_set(vid, value)
    else
      @function.rb_hash_aset(@dynavars.get, vid, value)
    end
  end

  # Get a dynamic variable.
  #
  # Set also #dyn_set.
  #
  # +vid+:: a Symbol with the name of the variable to get
  def dyn_get(vid)
    if local_defined(vid) then
      return local_get(vid)
    else
      value = @function.rb_hash_aref(@dynavars.get, vid)
      return value
    end
  end

  # Returns a JIT::Value containing true if the given dynamic variable
  # has been defined, a JIT::Value containing false otherwise.
  #
  # This differs from local_defined(), which returns true or false (not
  # as a JIT::Value), because the value of dyn_defined() cannot be
  # determined statically (by the very nature of dynamic variables).
  #
  # +vid+:: a Symbol with the name of the variable to test
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

