class VM
  class Instruction
    def set_source(function)
      # TODO
    end

    class PUTOBJECT
      def ludicrous_compile(function, env)
        value = function.const(JIT::Type::OBJECT, self.operands[0])
        env.stack.push(value)
      end
    end

    class LEAVE
      def ludicrous_compile(function, env)
        retval = env.stack.pop
        function.insn_return(retval)
      end
    end

    class OPT_PLUS
      def ludicrous_compile(function, env)
        rhs = env.stack.pop
        lhs = env.stack.pop

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
        env.stack.sync_sp()
        result.store(function.rb_funcall(lhs, :+, rhs))

        function.insn_label(end_label)

        env.stack.push(result)
      end
    end

    class OPT_MINUS
      def ludicrous_compile(function, env)
        rhs = env.stack.pop
        lhs = env.stack.pop

        result = function.value(JIT::Type::OBJECT)

        end_label = JIT::Label.new

        function.if(lhs.is_fixnum) {
          function.if(rhs.is_fixnum) {
            # TODO: This optimization is only valid if Fixnum#+ has not
            # been redefined.  Fortunately, YARV gives us
            # ruby_vm_redefined_flag, which we can check.
            env.stack.sync_sp
            function.insn_branch(end_label)
          } .end
        } .end

        set_source(function)
        env.stack.sync_sp()
        result.store(function.rb_funcall(lhs, :-, rhs))

        function.insn_label(end_label)

        env.stack.push(result)
      end
    end

    class DUP
      def ludicrous_compile(function, env)
        env.stack.push(env.stack.top)
      end
    end

    class SETLOCAL
      def ludicrous_compile(function, env)
        name = env.local_variable_name(@operands[0])
        value = env.stack.pop
        env.scope.local_set(name, value)
      end
    end

    class GETLOCAL
      def ludicrous_compile(function, env)
        name = env.local_variable_name(@operands[0])
        env.stack.push(env.scope.local_get(name))
      end
    end
  end
end

