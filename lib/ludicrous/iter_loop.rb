module Ludicrous
  ITER_ARG_TYPE = JIT::Struct.new(
      [ :recv, JIT::Type::OBJECT ],
      [ :scope, JIT::Type::OBJECT ])

  class IterArg
    attr_reader :env

    def self.new(function, env, recv)
      obj = self.allocate
      obj.instance_eval do
        @iter_arg = ITER_ARG_TYPE.create(function)
        @iter_arg.recv = recv || function.const(JIT::Type::OBJECT, nil)
        @iter_arg.scope = env.scope.scope_obj
      end
      return obj
    end

    def ptr
      return @iter_arg.ptr
    end

    def recv
      return @iter_arg.recv
    end

    def scope
      return @iter_arg.scope
    end

    def self.wrap(value)
      obj = self.allocate
      obj.instance_eval do
        @iter_arg = ITER_ARG_TYPE.wrap(value)
      end
      return obj
    end
  end

  class IterLoop
    def initialize(function)
      @function = function
      @start_label = JIT::Label.new
      @function.insn_label(@start_label)
    end

    def break
      @function.rb_iter_break()
    end

    def redo
      @function.insn_branch(@start_label)
    end
  end
end

