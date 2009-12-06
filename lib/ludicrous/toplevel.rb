require 'ludicrous/yarv_vm'
require 'ludicrous/compile_options'

class Node

# Compile this node as if it were the toplevel node of a Ruby program.
#
# +toplevel_self+:: the toplevel self
# +compile_options+:: a CompileOptions object indicating how this node
# is to be compiled
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

if defined?(RubyVM) then

class RubyVM
  # Compile this instruction sequence as if it were the toplevel
  # instruction sequence of a Ruby program.
  #
  # +toplevel_self+:: the toplevel self
  # +compile_options+:: a CompileOptions object indicating how this node
  # is to be compiled
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

          # puts self.disasm

          # LEAVE instruction should generate return instruction
          self.ludicrous_compile(f, env)
        end

        return function
      end

    end # def ludicrous_compile_toplevel
  end # class InstructionSequence
end # class RubyVM

end # if defined?(RubyVM)

class String
  if defined?(RubyVM) then
    # >= 1.9

    # Compile this node as if it were the toplevel code of a Ruby program.
    #
    # +toplevel_self+:: the toplevel self
    # +compile_options+:: a CompileOptions object indicating how this node
    # is to be compiled
    def ludicrous_compile_toplevel(
        toplevel_self = Object.new,
        compile_options = Ludicrous::CompileOptions.new)
      node = Node.compile_string(self)
      iseq = node.bytecode_compile() # TODO: name/filename
      return iseq.ludicrous_compile_toplevel(toplevel_self)
    end
  else
    # <= 1.8

    # Compile this node as if it were the toplevel code of a Ruby program.
    #
    # +toplevel_self+:: the toplevel self
    # +compile_options+:: a CompileOptions object indicating how this node
    # is to be compiled
    def ludicrous_compile_toplevel(
        toplevel_self = Object.new,
        compile_options = Ludicrous::CompileOptions.new)
      node = Node.compile_string(self)
      return node.ludicrous_compile_toplevel(toplevel_self)
    end
  end
end

