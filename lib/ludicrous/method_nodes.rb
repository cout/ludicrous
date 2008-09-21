require 'internal/method/signature'
require 'internal/proc/signature'

class Node

module DynamicVariableScopeInfo
  def ludicrous_scope_info
    return true, [ self.vid ]
  end
end

class DASGN_CURR
  include DynamicVariableScopeInfo
end

class DASGN
  include DynamicVariableScopeInfo
end

class DVAR
  include DynamicVariableScopeInfo
end

module DefinitionScopeInfo
  def ludicrous_scope_info
    # TODO
    return false, [ ]
  end
end

class MODULE
  include DefinitionScopeInfo
end

class CLASS
  include DefinitionScopeInfo
end

class DEFN
  include DefinitionScopeInfo
end

class DEFS
  include DefinitionScopeInfo
end

module LocalScopeInfo
  def ludicrous_scope_info
    needs_addressable_scope, vars = super
    vars << self.vid
    return needs_addressable_scope, vars
  end
end

def ludicrous_scope_info
  klass = self.class
  vars = []

  if klass.const_defined?(:LIBJIT_NEEDS_ADDRESSABLE_SCOPE) then
    needs_addressable_scope = true
  else
    needs_addressable_scope = false
  end

  members.each do |name|
    member = self[name]
    if Node === member then
      member_needs_addressable_scope, member_vars = member.ludicrous_scope_info
      needs_addressable_scope ||= member_needs_addressable_scope
      vars.concat(member_vars)
    end
  end

  return needs_addressable_scope, vars
end

class MethodNodeCompiler
  attr_reader :node
  attr_reader :origin_class
  attr_reader :compile_options

  attr_reader :arg_names
  attr_reader :args
  attr_reader :has_optional_params

  def initialize(node, origin_class, compile_options)
    @node = node
    @origin_class = origin_class
    @compile_options = compile_options

    @arg_names = node.argument_names
    @args = node.arguments

    @has_optional_params = false
    @args.each do |name, arg|
      @has_optional_params = true if arg.optional?
    end
  end

  def create_arguments_compiler
    if @has_optional_params then
      # some arguments are optional for this method
      @arguments_compiler = VariableArgumentsCompiler.new(
          @arg_names,
          @args,
          @node)
    else
      # all arguments required for this method
      @arguments_compiler = FixedArgumentsCompiler.new(
          @arg_names)
    end
  end

  def jit_signature
    return @variable_compiler.jit_signature
  end

  def create_environment(function)
    return self.node.ludicrous_create_environment(self, function)
  end

  def compile
    arguments_compiler = create_arguments_compiler()
    signature = arguments_compiler.jit_signature

    JIT::Context.build do |context|
      function = JIT::Function.compile(context, signature) do |f|
        f.optimization_level = @compile_options.optimization_level

        env = create_environment(f)

        begin
          arguments_compiler.compile_assign_arguments(env)

          yield(f, env)
        rescue Exception
          if env.file and env.line then
            $!.message << " at #{env.file}:#{env.line}"
          end
          raise
        end
      end

      # puts function.dump
      # exit
      return function
    end
  end
end

class ArgumentsCompiler
  def initialize(arg_names)
    @arg_names = arg_names
  end
end

class FixedArgumentsCompiler < ArgumentsCompiler
  def initialize(arg_names)
    super(arg_names)
  end

  def jit_signature
    return JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT ] * (1 + @arg_names.size))
  end

  def compile_assign_arguments(env)
    env.scope.self = env.function.get_param(0)
    @arg_names.each_with_index do |arg_name, idx|
      # TODO: how to deal with default values?
      env.scope.arg_set(arg_name, env.function.get_param(idx+1))
    end
  end
end

class VariableArgumentsCompiler < ArgumentsCompiler
  def initialize(arg_names, args, node)
    super(arg_names)

    @args = args
    @node = node

    @optional_args = @args.dup
    @optional_args.delete_if { |name, arg| !arg.optional? }
  end

  def jit_signature
    return JIT::Type::RUBY_VARARG_SIGNATURE
  end

  def compile_assign_arguments(env)
    # TODO: Create a JIT::Array?
    argc = env.function.get_param(0)
    argv = env.function.get_param(1)
    env.scope.self = env.function.get_param(2)

    @arg_names.each_with_index do |arg_name, idx|
      arg = @args[arg_name]
      if arg.required? then
        self.compile_assign_required_argument(env, arg, idx, argc, argv)
      elsif arg.rest?
        self.compile_assign_rest_argument(env, arg, idx, argc, argv)
      elsif arg.block?
        self.compile_assign_block_argument(env, arg, idx, argc, argv)
      else
        self.compile_assign_optional_argument(env, arg, idx, argc, argv)
      end
    end
  end

  def compile_assign_required_argument(env, arg, idx, argc, argv)
    # TODO: 64-bit safe?
    # (even so, I need to comment why I'm multiplying idx by 4)
    val = env.function.insn_load_relative(argv, idx * 4, JIT::Type::OBJECT)
    env.scope.arg_set(arg.name, val)
  end

  def compile_assign_rest_argument(env, arg, idx, argc, argv)
    var_idx = env.function.const(JIT::Type::INT, idx)
    env.function.if(argc > var_idx) {
      # TODO: not 64-bit safe?
      rest = env.function.rb_ary_new4(
          argc - var_idx,
          argv + var_idx * env.function.const(JIT::Type::UINT, 4))
      env.scope.rest_arg_set(arg.name, rest)
    } .else {
      rest = env.function.rb_ary_new()
      env.scope.rest_arg_set(arg.name, rest)
    } .end
  end

  def compile_assign_block_argument(env, arg, idx, argc, argv)
    raise "Can't handle block arg"
  end

  def compile_assign_optional_argument(env, arg, idx, argc, argv)
    val = env.function.value(JIT::Type::OBJECT)
    var_idx = env.function.const(JIT::Type::INT, idx)

    env.function.if(var_idx < argc) {
      # this arg was passed in
      # TODO: 64-bit safe?
      # (even so, I need to comment why I'm multiplying idx by 4)
      val.store(env.function.insn_load_relative(
          argv,
          idx * 4,
          JIT::Type::OBJECT))
    } .else {
      # this arg was not passed in
      arg = @optional_args[arg.name]
      val.store(@node.ludicrous_compile_optional_argument(arg))
    } .end

    env.scope.arg_set(arg.name, val)
  end
end

class SCOPE
  def ludicrous_create_scope(compiler, function)
    needs_addressable_scope, var_names = self.next.ludicrous_scope_info
    var_names.concat compiler.arg_names
    var_names.uniq!

    scope_type = needs_addressable_scope \
      ? Ludicrous::AddressableScope \
      : Ludicrous::Scope
    scope = scope_type.new(function, var_names)
  end

  def ludicrous_create_environment(compiler, function)
    scope = ludicrous_create_scope(compiler, function)
    env = Ludicrous::Environment.new(
        function,
        compiler.compile_options,
        compiler.origin_class,
        scope)
  end

  def ludicrous_compile_optional_argument(arg)
    node = arg.node_or_iseq_for_default
    return node.ludicrous_compile(env.function, env)
  end

  def ludicrous_compile_into_function(
      origin_class,
      compile_options = Ludicrous::CompileOptions.new)

    compiler = MethodNodeCompiler.new(
        self,
        origin_class,
        compile_options)

    compiler.compile do |function, env|
      result = self.ludicrous_compile(function, env)
      if not result.is_returned then
        function.insn_return(result)
      end
    end
  end
end

class METHOD
  def ludicrous_create_scope(compiler, function)
    needs_addressable_scope = true # TODO
    var_names = self.body.local_table
    var_names.concat compiler.arg_names
    var_names.uniq!

    scope_type = needs_addressable_scope \
      ? Ludicrous::AddressableScope \
      : Ludicrous::Scope
    scope = scope_type.new(function, var_names)
  end

  def ludicrous_create_environment(compiler, function)
    scope = ludicrous_create_scope(compiler, function)
    env = Ludicrous::YarvEnvironment.new(
        function,
        compiler.compile_options,
        compiler.origin_class,
        scope,
        self.body)
  end

  def ludicrous_compile_optional_argument(arg)
    raise "Unable to compile optional argument"
  end

  def ludicrous_compile_into_function(
      origin_class,
      compile_options = Ludicrous::CompileOptions.new)

    compiler = MethodNodeCompiler.new(
        self,
        origin_class,
        compile_options)

    #
    # puts self.body.disasm

    compiler.compile do |function, env|
      # LEAVE instruction should generate return instruction
      self.body.ludicrous_compile(function, env)
    end
  end
end

class IVAR
  def ludicrous_compile_into_function(
      origin_class,
      options = Ludicrous::CompileOptions.new)
    raise "Not JIT-compiling IVAR (would be slower)"
  end
end

class CFUNC
  def ludicrous_compile_into_function(
      origin_class,
      options = Ludicrous::CompileOptions.new)
    raise "Cannot jit-compile C function"
  end
end

end # class Node

