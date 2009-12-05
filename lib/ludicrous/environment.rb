require 'ludicrous/stack'
require 'ludicrous/iter_loop'

module Ludicrous

# An encapsulation for the state used when compiling a method.
class Environment
  attr_reader :function
  attr_reader :scope
  attr_accessor :options
  attr_reader :cbase
  attr_accessor :file
  attr_accessor :line

  # Create a new Environment
  #
  # +function+:: the JIT::Function currently being compiled
  # +options+:: a Ludicrous::CompileOptions object indicating what
  # options should be used when compiling the method
  # +cbase+:: the cbase to use for constant lookup
  # +scope+:: the current lexical scope (should be of type Scope or
  # AddressableScope)
  def initialize(function, options, cbase, scope)
    @function = function
    @options = options
    @cbase = cbase
    @scope = scope
    @scope_stack = []
    @loop_end_labels = []
    @loops = []
    @file = nil
    @line = nil
    @iter = false
  end

  # Create a new Environment from an outer environment (used when
  # iterating; the function created for the block needs access to the
  # scope for the outer function)
  #
  # +function+:: the JIT::Function for the inner block
  # +inner_scope+:: the scope for the inner block (should be an
  # AddressableScope)
  # +outer_env+:: the environment for the outer scope (should have been
  # created with an AddressableScope)
  def self.from_outer(function, inner_scope, outer_env)
    return self.new(
        function,
        outer_env.options,
        outer_env.cbase,
        inner_scope)
  end

  # Emit code to iterate over the the code emitted by the given block.
  #
  # Yields an IterLoop object that can be used to control iteration
  # behavior (break/redo).  This loop is pushed onto the loop stack so
  # that +env.break+ and +env.redo+ will operate on this loop.
  #
  # Returns the result of the block.
  #
  # Example (for an infinite loop):
  #
  #   v = f.value(:INT, 0)
  #   env.iter { |loop|
  #     v.store(v+1)
  #   }
  def iter(&block)
    loop = 
    iter = @iter
    begin
      @iter = true
      loop(loop, &block)
    ensure
      @iter = iter
    end
  end

  # Emit code to return from the function currently being compiled.
  def return(value)
    if @iter then
      raise "Can't return from inside an iterator"
    else
      @function.insn_return(value)
    end
  end

  # Pushes the given loop onto the loop stack so that +env.break+ and
  # +env.redo+ will operate on this loop.  Does not actually do any
  # looping; this must be taken care of by the loop object in the outer
  # block.
  #
  # +loop+:: an object that responds to #redo and #break (usually either
  # an IterLoop or a JIT::Function::Loop).
  def loop(loop, &block)
    @loop_end_labels.push(JIT::Label.new)
    @loops.push(loop)

    begin
      retval = yield loop
    ensure
      @loops.pop
      @function.insn_label(@loop_end_labels.pop)
    end
    return retval
  end

  # Calls +redo+ on the most topmost loop on the loop stack.
  def redo
    @loops[-1].redo
  end

  # Emits code to branch to the end of the loop so it can be restarted.
  def next
    @function.insn_branch(@loop_end_labels[-1])
  end

  # Calls +break+ on the topmost loop on the loop stack.
  def break
    @loops[-1].break
  end

  # Find a constant, searching the environment's cref.
  #
  # +vid+:: Symbol for the constant to search for.
  def get_constant(vid)
    # TODO: search whole const ref list, not just a single class
    # TODO: set source before calling function
    return @function.rb_const_get(@cbase, vid)
  end

  # Search the environment's cref to determine if a constant is defined.
  #
  # +vid+:: Symbol for the constant to search for.
  def constant_defined(vid)
    # TODO: set source before calling function
    result = @function.value(JIT::Type::OBJECT)
    @function.if(@function.rb_const_defined(@cbase, vid)) {
      result.store(@function.const(JIT::Type::OBJECT, "constant"))
    } .else {
      result.store(@function.const(JIT::Type::OBJECT, false))
    } .end
    return result
  end
end

end # Ludicrous

