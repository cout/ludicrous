class Node

def ludicrous_scope_info
  klass = self.class

  if klass == Node::DASGN_CURR or \
     klass == Node::DASGN or \
     klass == Node::DVAR then
    return true, [ self.vid ]
  end

  if klass == Node::MODULE or \
     klass == Node::CLASS or \
     klass == Node::DEFN or \
     klass == Node::DEFS then
    # TODO
    return false, [ ]
  end

  vars = []
  if klass == Node::LASGN or \
     klass == Node::LVAR then
    vars << self.vid
  end

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

def ludicrous_compile_toplevel(toplevel_self, options = Ludicrous::Options.new)
  signature = JIT::Type.create_signature(
    JIT::ABI::CDECL,
    JIT::Type::OBJECT,
    [ ])

  JIT::Context.build do |context|
    function = JIT::Function.compile(context, signature) do |f|
      f.optimization_level = options.optimization_level

      needs_addressable_scope, vars = self.next.ludicrous_scope_info
      vars.uniq!
      scope_type = needs_addressable_scope \
        ? Ludicrous::AddressableScope \
        : Ludicrous::Scope
      scope = scope_type.new(f, vars)

      origin_class = f.const(JIT::Type::OBJECT, toplevel_self.class) # TODO: is this right?

      env = Ludicrous::Environment.new(
          f,
          options,
          origin_class,
          scope)

      env.scope.self = f.const(JIT::Type::OBJECT, toplevel_self)

      result = self.ludicrous_compile(f, env)
      if not result then
        f.insn_return(f.const(JIT::Type::OBJECT, nil))
      elsif not result.is_returned then
        f.insn_return(result)
      end
    end

    return function
  end
end

class SCOPE
  def ludicrous_compile_into_function(origin_class, options = Ludicrous::Options.new)
    arg_names = self.argument_names
    args = self.arguments

    has_optional_params = false
    args.each do |name, arg|
      has_optional_params = true if arg.optional?
    end

    if not has_optional_params then
      # all arguments required for this method
      signature = JIT::Type.create_signature(
        JIT::ABI::CDECL,
        JIT::Type::OBJECT,
        [ JIT::Type::OBJECT ] * (1 + arg_names.size))
    else
      # some arguments are optional for this method
      signature = JIT::Type::RUBY_VARARG_SIGNATURE
    end

    JIT::Context.build do |context|
      function = JIT::Function.compile(context, signature) do |f|
        f.optimization_level = options.optimization_level

        needs_addressable_scope, var_names = self.next.ludicrous_scope_info
        var_names.concat arg_names
        var_names.uniq!
        scope_type = needs_addressable_scope \
          ? Ludicrous::AddressableScope \
          : Ludicrous::Scope
        scope = scope_type.new(f, var_names)
        env = Ludicrous::Environment.new(
            f,
            options,
            origin_class,
            scope)

        begin
          if not has_optional_params then
            # all arguments required for this method
            env.scope.self = f.get_param(0)
            arg_names.each_with_index do |arg_name, idx|
              # TODO: how to deal with default values?
              env.scope.arg_set(arg_name,  f.get_param(idx+1))
            end
          else
            # some arguments are optional for this method
            optional_args = args.dup
            optional_args.delete_if { |name, arg| !arg.optional? }

            argc = f.get_param(0)
            argv = f.get_param(1)
            env.scope.self = f.get_param(2)

            arg_names.each_with_index do |arg_name, idx|
              arg = args[arg_name]
              if arg.required? then
                # required arg
                val = f.insn_load_relative(argv, idx*4, JIT::Type::OBJECT)
                env.scope.arg_set(arg_name, val)
              elsif arg.rest?
                var_idx = f.const(JIT::Type::INT, idx)
                f.if(argc > var_idx) {
                  rest = f.rb_ary_new4(argc - var_idx, argv + var_idx*f.const(JIT::Type::UINT, 4)) # TODO
                  env.scope.rest_arg_set(arg_name, rest)
                } .else {
                  rest = f.rb_ary_new()
                  env.scope.rest_arg_set(arg_name, rest)
                } .end
              elsif arg.block?
                raise "Can't handle block arg"
              else
                # optional arg
                val = f.value(JIT::Type::OBJECT)
                var_idx = f.const(JIT::Type::INT, idx)
                f.if(var_idx < argc) {
                  # this arg was passed in
                  val.store(f.insn_load_relative(argv, idx*4, JIT::Type::OBJECT))
                } .else {
                  # this arg was not passed in
                  val.store(optional_args[arg_name].node_or_iseq_for_default.ludicrous_compile(f, env))
                } .end
                env.scope.arg_set(arg_name, val)
              end
            end
          end

          # require 'nodepp'
          # pp self
          result = self.ludicrous_compile(f, env)
          if not result.is_returned then
            f.insn_return(result)
          end
          # puts f.dump
          # puts "About to compile..."
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

class METHOD
  def ludicrous_compile_into_function(origin_class, options = Ludicrous::Options.new)
    # TODO
    arg_names = []

    signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT ] * (1 + arg_names.size))

    JIT::Context.build do |context|
      function = JIT::Function.compile(context, signature) do |f|
        # TODO: args
        # TODO: body
        # TODO: return value
        result = f.const(JIT::Type::INT, Ludicrous::Qnil)
        f.insn_return(result)
      end
    end
  end
end

class CFUNC
  def ludicrous_compile(function, env)
    raise "Cannot jit-compile C function"
  end
end

end # class Node

