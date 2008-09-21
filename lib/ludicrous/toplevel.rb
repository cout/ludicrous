class Node

def ludicrous_compile_toplevel(
    toplevel_self,
    compile_options = Ludicrous::CompileOptions.new)

  signature = JIT::Type.create_signature(
    JIT::ABI::CDECL,
    JIT::Type::OBJECT,
    [ ])

  JIT::Context.build do |context|
    function = JIT::Function.compile(context, signature) do |f|
      f.optimization_level = compile_options.optimization_level

      needs_addressable_scope, vars = self.ludicrous_scope_info
      vars.uniq!
      scope_type = needs_addressable_scope \
        ? Ludicrous::AddressableScope \
        : Ludicrous::Scope
      scope = scope_type.new(f, vars)

      origin_class = f.const(JIT::Type::OBJECT, toplevel_self.class) # TODO: is this right?

      env = Ludicrous::Environment.new(
          f,
          compile_options,
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

end

if defined?(VM) then

class VM
  class InstructionSequence
    def ludicrous_compile_toplevel(
      toplevel_self,
      compile_options = Ludicrous::CompileOptions.new)

      signature = JIT::Type.create_signature(
        JIT::ABI::CDECL,
        JIT::Type::OBJECT,
        [ ])

      JIT::Context.build do |context|
        function = JIT::Function.compile(context, signature) do |f|
          f.optimization_level = compile_options.optimization_level

          needs_addressable_scope = true # TODO
          vars = self.local_table
          vars.uniq!
          scope_type = needs_addressable_scope \
            ? Ludicrous::AddressableScope \
            : Ludicrous::Scope
          scope = scope_type.new(f, vars)

          origin_class = f.const(JIT::Type::OBJECT, toplevel_self.class) # TODO: is this right?

          env = Ludicrous::YarvEnvironment.new(
              f,
              compile_options,
              origin_class,
              scope,
              self)

          env.scope.self = f.const(JIT::Type::OBJECT, toplevel_self)

          # LEAVE instruction should generate return instruction
          self.ludicrous_compile(f, env)
        end

        return function
      end

    end # def ludicrous_compile_toplevel
  end # class InstructionSequence
end # class VM

end # if defined?(VM)

class String
  if defined?(VM) then
    # >= 1.9
    def ludicrous_compile_toplevel(toplevel_self = Object.new)
      node = Node.compile_string(self)
      iseq = node.bytecode_compile() # TODO: name/filename
      return iseq.ludicrous_compile_toplevel(toplevel_self)
    end
  else
    # <= 1.8
    def ludicrous_compile_toplevel(toplevel_self = Object.new)
      node = Node.compile_string(self)
      return node.ludicrous_compile_toplevel(toplevel_self)
    end
  end
end

