require 'ludicrous/yarv_vm'
require 'ludicrous/iter_loop'
require 'ludicrous/ruby_types'
require 'internal/vm/constants'

class RubyVM
  class Instruction
    def set_source(function)
      # TODO
    end

    class TRACE
      def ludicrous_compile(function, env)
      end
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

    class TOSTRING
      def ludicrous_compile(function, env)
        obj = env.stack.pop
        str = function.rb_obj_as_string(obj)
        env.stack.push(str)
      end
    end

    class CONCATSTRINGS
      def ludicrous_compile(function, env)
        num = @operands[0]
        # TODO: I'm pretty sure this is implemented wrong
        str = function.rb_str_dup("") # TODO: rb_str_new
        strings = (0...num).collect { env.stack.pop }
        strings.reverse.each do |x|
          function.rb_str_concat(str, x) # TODO: rb_str_append
        end
        env.stack.push(str)
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

    class PUTSPECIALOBJECT
      def ludicrous_compile(function, env)
        value_type = @operands[0]
        case value_type
        when RubyVM::SPECIAL_OBJECT_VMCORE
          value = function.const(
              JIT::Type::OBJECT,
              Ludicrous::RUBY_VM_FROZEN_CORE)
        when RubyVM::SPECIAL_OBJECT_CBASE
          value = env.cbase
        else
          raise "Invalid special value type #{value_type}"
        end

        env.stack.push(value)
      end
    end

    class PUTISEQ
      def ludicrous_compile(function, env)
        iseq = @operands[0]
        env.stack.push(iseq)
      end
    end

    class LEAVE
      def ludicrous_compile(function, env)
        retval = env.stack.pop
        function.insn_return(retval)
      end
    end

    def ludicrous_compile_binary_op(args)
      function = args[:function]
      env = args[:env]
      operator = args[:operator]
      fixnum_proc = args[:fixnum]

      rhs = env.stack.pop
      lhs = env.stack.pop

      result = function.value(JIT::Type::OBJECT)

      end_label = JIT::Label.new

      function.if(lhs.is_fixnum & rhs.is_fixnum) {
        # TODO: This optimization is only valid if Fixnum#+ has not
        # been redefined.  Fortunately, YARV gives us
        # ruby_vm_redefined_flag, which we can check.
        result.store(fixnum_proc.call(lhs, rhs))
        function.insn_branch(end_label)
      } .end

      set_source(function)
      env.stack.sync_sp()
      result.store(function.rb_funcall(lhs, operator, rhs))

      function.insn_label(end_label)

      env.stack.push(result)
    end

    class OPT_PLUS
      def ludicrous_compile(function, env)
        ludicrous_compile_binary_op(
            :function => function,
            :env      => env,
            :operator => :+,
            :fixnum   => proc { |lhs, rhs|
              lhs + (rhs & function.const(JIT::Type::INT, ~1)) }
            )
      end
    end

    class OPT_MINUS
      def ludicrous_compile(function, env)
        ludicrous_compile_binary_op(
            :function => function,
            :env      => env,
            :operator => :-,
            :fixnum   => proc { |lhs, rhs|
              lhs - (rhs & function.const(JIT::Type::INT, ~1)) }
            )
      end
    end

    class OPT_NEQ
      def ludicrous_compile(function, env)
        ludicrous_compile_binary_op(
            :function => function,
            :env      => env,
            :operator => :!=,
            :fixnum   => proc { |lhs, rhs|
              lhs.neq(rhs).to_rbool }
            )
      end
    end

    def ludicrous_compile_unary_op(args)
      function = args[:function]
      env = args[:env]
      operator = args[:operator]
      fixnum_proc = args[:fixnum]

      operand = env.stack.pop

      result = function.value(JIT::Type::OBJECT)

      end_label = JIT::Label.new

      function.if(operand.is_fixnum) {
        # TODO: This optimization is only valid if Fixnum#<operator> has
        # not been redefined.  Fortunately, YARV gives us
        # ruby_vm_redefined_flag, which we can check.
        result.store(fixnum_proc.call(operand))
        function.insn_branch(end_label)
      } .end

      set_source(function)
      env.stack.sync_sp()
      result.store(function.rb_funcall(operand, operator))

      function.insn_label(end_label)

      env.stack.push(result)
    end

    class OPT_NOT
      def ludicrous_compile(function, env)
        operand = env.stack.pop
        env.stack.push(operand.rnot)
      end
    end

    class OPT_AREF
      def ludicrous_compile(function, env)
        obj = env.stack.pop
        recv = env.stack.pop

        result = function.rb_funcall(recv, :[], obj)
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

    class EXPANDARRAY
      class Flags
        attr_reader :is_splat
        attr_reader :is_post
        attr_reader :is_normal

        def initialize(flags)
          @is_splat = (flags & 0x1) != 0
          @is_post = (flags & 0x2) != 0
          @is_normal = !@is_post
        end
      end

      def ludicrous_compile(function, env)
        num = @operands[0]
        flags = Flags.new(@operands[1])

        # TODO: insn_dup does not dup constants, so we do this -- is
        # there a better way?
        ary = env.stack.pop
        # ary = function.insn_dup(ary)
        ary = ary + function.const(JIT::Type::INT, 0)

        function.unless(ary.is_type(Ludicrous::T_ARRAY)) {
          ary.store(function.rb_ary_to_ary(ary))
        }.end

        if flags.is_post then
          ludicrous_compile_post(function, env, ary, num, flags)
        else
          ludicrous_compile_normal(function, env, ary, num, flags)
        end
      end

      def ludicrous_compile_post(function, env, ary, num, flags)
        raise "Not implemented"
      end

      def ludicrous_compile_normal(function, env, ary, num, flags)
        if flags.is_splat then
          remainder = function.rb_funcall(ary, :[], 0..num)
          env.stack.push(remainder)
        end
        (num-1).downto(0) do |i|
          env.stack.push(function.rb_ary_at(ary, i))
        end
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
        value = env.scope.local_get(name)
        env.stack.push(value)
      end
    end

    class GETGLOBAL
      def ludicrous_compile(function, env)
        name = @operands[0]

        if name == '$!'.intern then
          # TODO: the global errinfo getter looks in the control frame
          # for $! -- should we be setting errinfo there?
          value = function.rb_errinfo()
        else
          ptr = function.rb_string_value_ptr(name_str.address)
          name_str = function.value(JIT::Type::OBJECT)
          name_str.store(function.const(JIT::Type::OBJECT, name.to_s))
          value = function.rb_gv_get(ptr)
        end

        env.stack.push(value)
      end
    end

    class GETDYNAMIC
      def ludicrous_compile(function, env)
        idx = @operands[0]
        level = @operands[1]

        # TODO: we use level to determine the name, but we should also
        # use it when finding the variable
        name = env.dyn_variable_name(idx, level)

        # TODO: I don't know if this is right
        if name == '#$!'.intern then
          value = function.rb_errinfo()
        else
          value = env.scope.dyn_get(name)
        end

        env.stack.push(value)
      end
    end

    class GETCONSTANT
      def ludicrous_compile(function, env)
        klass = env.stack.pop
        vid = @operands[0]

        # TODO: can determine this at compile-time
        result = function.value(JIT::Type::OBJECT)
        function.if(klass == function.const(JIT::Type::OBJECT, nil)) {
          result.store(env.get_constant(vid))
        }.else {
          result.store(function.rb_const_get(klass, vid))
        }.end

        env.stack.push(result)
      end
    end

    class JUMP
      def ludicrous_compile(function, env)
        relative_offset = @operands[0]
        env.branch_relative(relative_offset)
      end
    end

    class BRANCHIF
      def ludicrous_compile(function, env)
        relative_offset = @operands[0]
        val = env.stack.pop
        env.branch_relative_if(val.rtest, relative_offset)
      end
    end

    class BRANCHUNLESS
      def ludicrous_compile(function, env)
        relative_offset = @operands[0]
        val = env.stack.pop
        env.branch_relative_unless(val.rtest, relative_offset)
      end
    end

    def ludicrous_iterate(function, env, body, recv=nil)
      # body - the iseq for body of the loop
      # recv -
      # 1. compile a nested function from the body of the loop
      # 2. pass this nested function as a parameter to 

      iter_signature = JIT::Type.create_signature(
          JIT::ABI::CDECL,
          JIT::Type::OBJECT,
          [ JIT::Type::VOID_PTR ])
      iter_f = JIT::Function.compile(function.context, iter_signature) do |f|
        f.optimization_level = env.options.optimization_level

        iter_arg = Ludicrous::IterArg.wrap(f.get_param(0))
        inner_scope = Ludicrous::AddressableScope.load(
            f, iter_arg.scope, env.scope.local_names,
            env.scope.args, env.scope.rest_arg)
        inner_env = Ludicrous::YarvBaseEnvironment.new(
            f, env.options, env.cbase, iter_arg.scope)

        result = yield(f, inner_env, iter_arg.recv)
        f.insn_return result
      end

      body_signature = JIT::Type::create_signature(
          JIT::ABI::CDECL,
          JIT::Type::OBJECT,
          [ JIT::Type::OBJECT, JIT::Type::VOID_PTR ])
      body_f = JIT::Function.compile(function.context, body_signature) do |f|
        f.optimization_level = env.options.optimization_level

        value = f.get_param(0)
        outer_scope_obj = f.get_param(1)
        inner_scope = Ludicrous::AddressableScope.load(
            f, outer_scope_obj, env.scope.local_names, env.scope.args,
            env.scope.rest_arg)
        inner_env = Ludicrous::YarvEnvironment.new(
            f, env.options, env.cbase, inner_scope, body)

        loop = Ludicrous::IterLoop.new(f)
        inner_env.iter(loop) {
          ludicrous_iter_arg_assign(f, inner_env, body, value)
          body.ludicrous_compile(f, inner_env)
        }
      end

      iter_arg = Ludicrous::IterArg.new(function, env, recv)

      # TODO: will this leak memory if the function is redefined later?
      iter_c = function.const(JIT::Type::FUNCTION_PTR, iter_f.to_closure)
      body_c = function.const(JIT::Type::FUNCTION_PTR, body_f.to_closure)
      set_source(function)

      result = function.rb_iterate(iter_c, iter_arg.ptr, body_c, iter_arg.scope)
      return result
    end

    def ludicrous_iter_arg_assign(function, env, body, rhs)
      function.if(rhs == nil) {
        for i in 0...(body.argc) do
          env.scope.dyn_set(body.local_table[i], nil)
        end
      }.else {

        array = Ludicrous::RArray.wrap(rhs)

        if not body.arg_simple then
          raise "Cannot handle non-simple block arguments"
        end

        # TODO: size check?
        for i in 0...(body.argc - 1) do
          # TODO: make sure the block argument is local to this scope
          idx = function.const(:INT, i)
          value = function.value(:OBJECT)
          function.if(idx < array.len) {
            value.store array[idx]
          }.else {
            value.store function.const(:OBJECT, nil)
          }.end
          env.scope.dyn_set(body.local_table[i], value)
        end

        if body.argc > 0 then
          i = body.argc - 1
          idx = function.const(:INT, i)
          function.if(idx < array.len) {
            # TODO: not 64-bit safe
            ary = function.rb_ary_new4(
                array.len - i,
                array.ptr + (i << 2))
            value.store(ary.avalue_splat)
          }.else {
            value.store(function.const(:OBJECT, nil))
          }.end
          env.scope.dyn_set(body.local_table[i], value)
        end
      }.end
    end

    class SEND
      def ludicrous_compile(function, env)
        mid = @operands[0]
        argc = @operands[1]
        blockiseq = @operands[2]
        flags = @operands[3]
        ic = @operands[4]

        if flags & RubyVM::CALL_ARGS_BLOCKARG_BIT != 0 then
          # TODO: set blockiseq
          raise "Block arg not supported"
        end

        if flags & RubyVM::CALL_ARGS_SPLAT_BIT != 0 then
          raise "Splat not supported"
        end

        if flags & RubyVM::CALL_VCALL_BIT != 0 then
          raise "Vcall not supported"
        end

        args = (1..argc).collect { env.stack.pop }
        args.reverse!

        if flags & RubyVM::CALL_FCALL_BIT != 0 then
          recv = env.scope.self
          env.stack.pop # nil
        else
          recv = env.stack.pop
        end

        # TODO: pull in optimizations from eval_nodes.rb
        env.stack.sync_sp()

        if blockiseq then
          result = ludicrous_iterate(function, env, blockiseq, recv) do |f, e, r|
            # TODO: args is still referencing the outer function
            f.rb_funcall(r, mid, *args)
          end
        else
          result = function.rb_funcall(recv, mid, *args)
          # TODO: not sure why this was here, maybe I was trying to
          # prevent a crash
          # result = function.const(JIT::Type::OBJECT, nil)
        end

        env.stack.push(result)
      end
    end

    class THROW
      def ludicrous_compile(function, env)
        throw_state = @operands[0]
        state = throw_state & 0xff
        flag = throw_state & 0x8000
        level = throw_state >> 16

        throwobj = env.stack.pop

        case state
        when 0, Tag::RETRY
          # continue throw
          function.rb_jump_tag(state)
        when Tag::RETURN
          env.return(throwobj)
        else
          raise "Cannot handle tag #{state}"
        end
      end
    end

    class GETINLINECACHE
      def ludicrous_compile(function, env)
        # ignore, for now
        env.stack.push(function.const(JIT::Type::OBJECT, nil))
      end
    end

    class SETINLINECACHE
      def ludicrous_compile(function, env)
        # ignore, for now
      end
    end

    class NOP
      def ludicrous_compile(function, env)
      end
    end

    class DEFINEMETHOD
      def ludicrous_compile(function, env)
        mid = @operands[0]
        iseq = @operands[1]
        is_singleton = @operands[2] != 0

        obj = env.stack.pop

        klass = is_singleton \
          ? function.rb_class_of(obj)
          : function.rb_class_of(env.scope.self) # TODO: cref->nd_clss

        # COPY_CREF(miseq->cref_stack, cref);
        # miseq->klass = klass;
        # miseq->defined_method_id = id;
        # newbody = NEW_NODE(RUBY_VM_METHOD_NODE, 0, miseq->self, 0);
        # rb_add_method(klass, id, newbody, noex);

        # TODO: set_source(function)

        # TODO: set cref on iseq
        # TODO: set klass on iseq
        # TODO: set defined_method_id on iseq

        newbody = function.rb_node_newnode(
            Node::METHOD,
            0,
            function.const(JIT::Type::OBJECT, iseq),
            0)

        function.rb_add_method(
            klass,
            function.const(JIT::Type::ID, mid),
            newbody,
            function.const(JIT::Type::INT, 0)) # TODO: noex
      end
    end
  end
end

