# Abstractions for helping to create ruby iterators at the C level.

module Ludicrous
  # The JIT::Type of the argument to the iterator function
  ITER_ARG_TYPE = JIT::Struct.new(
      [ :recv, JIT::Type::OBJECT ],
      [ :scope, JIT::Type::OBJECT ])

  # An abstraction for the argument to the iterator function.
  class IterArg
    attr_reader :env

    # Create a new IterArg.
    #
    # This method is normally called from the outer iteration function.
    #
    # +function+:: the JIT::Function for the outer scope
    # +env+:: the Ludicrous::Environment for the outer scope
    # +recv+:: if this is an iteration on an object, the receiver of the
    # iteration method (e.g. for arr.each { }, the receiver is arr)
    def self.new(function, env, recv)
      obj = self.allocate
      obj.instance_eval do
        @iter_arg = ITER_ARG_TYPE.create(function)
        @iter_arg.recv = recv || function.const(JIT::Type::OBJECT, nil)
        @iter_arg.scope = env.scope.scope_obj
      end
      return obj
    end

    # Wrap an existing IterArg pointer into an +ITER_ARG_TYPE+ object
    # (which this class abstracts).  Thus method is usually called from
    # the inner iteration function.
    def self.wrap(value)
      obj = self.allocate
      obj.instance_eval do
        @iter_arg = ITER_ARG_TYPE.wrap(value)
      end
      return obj
    end

    # Return a pointer to the underlying +ITER_ARG_TYPE+ structure.  The
    # pointer can be turned into a new 
    def ptr
      return @iter_arg.ptr
    end

    # Return the receiver that was passed in when the IterArg was
    # constructed.
    def recv
      return @iter_arg.recv
    end

    # Return the scope from the environment that was passed in when the
    # IterArg was constructed.
    def scope
      return @iter_arg.scope
    end
  end

  # An abstraction for a ruby iteration loop.  Should be constructed
  # inside the iteration function (the function that is passed to
  # +rb_iterate+).
  class IterLoop
    # Create a new IterLoop.
    #
    # Emits a label that can be used to restart the loop (with +redo+).
    # 
    # +function+:: the JIT::Function currently being compiled
    def initialize(function)
      @function = function
      @start_label = JIT::Label.new
      @function.insn_label(@start_label)
    end

    # Emit code to break out of a loop using +rb_iter_break+.
    def break
      @function.rb_iter_break()
    end

    # Emit code to restart the loop by jumping to the beginning of the
    # loop.
    def redo
      @function.insn_branch(@start_label)
    end
  end
end

