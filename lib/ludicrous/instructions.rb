class VM
  class Instruction
    def set_source(function)
      # TODO
    end

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

    class OPT_PLUS
      def ludicrous_compile(function, env)
        # TODO: not sure about the order I need to pop in
        rhs = env.pop
        lhs = env.pop

        result = function.value(JIT::Type::OBJECT)

        end_label = JIT::Label.new

        function.if(lhs.is_fixnum) {
          function.if(rhs.is_fixnum) {
            # TODO: This optimization is only valid if Fixnum#+ has not
            # been redefined.  Fortunately, YARV gives us
            # ruby_vm_redefined_flag, which we can check.
            result.store(lhs + (rhs & function.const(JIT::Type::INT, ~1)))
            function.insn_branch(end_label)
          } .end
        } .end

        set_source(function)
        env.sync_sp()
        result.store(function.rb_funcall(lhs, :+, rhs))

        function.insn_label(end_label)

        env.push(result)
      end
    end
  end
end

