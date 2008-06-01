class VM
  class Instruction
    class PUTOBJECT
      def ludicrous_compile(function, env)
        value = function.const(JIT::Type::OBJECT, self.operands[0])
        env.push(value)
      end
    end

    class LEAVE
      def ludicrous_compile(function, env)
        retval = env.pop
        function.insn_return(retval)
      end
    end
  end
end

