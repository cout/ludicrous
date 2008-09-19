require 'internal/vm/constants'

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

    class PUTSTRING
      def ludicrous_compile(function, env)
        str = function.const(JIT::Type::OBJECT, self.operands[0])
        env.stack.push(function.rb_str_dup(str))
      end
    end

    class PUTNIL
      def ludicrous_compile(function, env)
        env.stack.push(function.const(JIT::Type::OBJECT, nil))
      end
    end

    class PUTSELF
      def ludicrous_compile(function, env)
        env.stack.push(env.scope.self)
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
            result.store(lhs - (rhs & function.const(JIT::Type::INT, ~1)))
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

    class OPT_NEQ
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
            result.store(lhs.neq rhs)
            function.insn_branch(end_label)
          } .end
        } .end

        set_source(function)
        env.stack.sync_sp()
        result.store(function.rb_funcall(lhs, :!=, rhs))

        function.insn_label(end_label)

        env.stack.push(result)
      end
    end

    class DUP
      def ludicrous_compile(function, env)
        env.stack.push(env.stack.top)
      end
    end

    class DUPARRAY
      def ludicrous_compile(function, env)
        ary = @operands[0]
        env.stack.sync_sp()
        ary = function.rb_ary_dup(ary)
        env.stack.push(ary)
      end
    end

    class SPLATARRAY
      def ludicrous_compile(function, env)
        ary = env.stack.pop
        env.stack.sync_sp()
        env.stack.push(ary.splat)
      end
    end

    class NEWARRAY
      def ludicrous_compile(function, env)
        # TODO: possible to optimize this
        num = @operands[0]
        env.stack.sync_sp()
        ary = function.rb_ary_new2(num)
        num.times do
          env.stack.sync_sp
          function.rb_ary_push(ary, env.stack.pop)
        end
        env.stack.push(ary)
      end
    end

    class CONCATARRAY
      def ludicrous_compile(function, env)
        ary1 = env.stack.pop
        ary2 = env.stack.pop
        tmp1 = ary1.splat
        tmp2 = ary2.splat
        env.stack.sync_sp()
        env.stack.push(function.rb_ary_concat(tmp1, tmp2))
      end
    end

    class POP
      def ludicrous_compile(function, env)
        env.stack.pop
      end
    end

    class SETN
      def ludicrous_compile(function, env)
        n = @operands[0]
        env.stack.setn(n, env.stack.pop)
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

    class JUMP
      def ludicrous_compile(function, env)
        relative_offset = @operands[0]
        env.branch(relative_offset)
      end
    end

    class BRANCHIF
      def ludicrous_compile(function, env)
        relative_offset = @operands[0]
        val = env.stack.pop
        env.branch_if(val.rtest, relative_offset)
      end
    end

    class SEND
      def ludicrous_compile(function, env)
        mid = @operands[0]
        argc = @operands[1]
        blockiseq = @operands[2]
        flags = @operands[3]
        ic = @operands[4]

        if flags & VM::CALL_ARGS_BLOCKARG_BIT != 0 then
          raise "Block arg not supported"
        end

        if flags & VM::CALL_ARGS_SPLAT_BIT != 0 then
          raise "Splat not supported"
        end

        if flags & VM::CALL_VCALL_BIT != 0 then
          raise "Vcall not supported"
        end

        args = (1..argc).collect { env.stack.pop }

        if flags & VM::CALL_FCALL_BIT != 0 then
          recv = env.scope.self
        else
          recv = env.stack.pop
        end

        # TODO: pull in optimizations from eval_nodes.rb
        env.stack.sync_sp()
        result = function.rb_funcall(recv, mid, *args)
        env.stack.push(result)
      end
    end

    class GETINLINECACHE
      def ludicrous_compile(function, env)
        # ignore, for now
        env.stack.push(function.const(JIT::Type::OBJECT, nil))
      end
    end

  end
end

