module Ludicrous

# An abstraction for a variable local to a particular Ruby method.
class LocalVariable
  # Create a new LocalVariable.
  #
  # +function+:: the JIT::Function for the method being compiled
  # +name+:: the name of the variable as a Symbol
  def initialize(function, name)
    @function = function
    @name = name
    @addressable = false
    @value = @function.value(JIT::Type::OBJECT)
  end

  # Emit code to initialize this variable to +nil+.
  def init
    self.set(@function.const(JIT::Type::OBJECT, nil))
  end

  # Emit code to set this variable to the +value+.
  #
  # +value+:: the value to set this variable to
  def set(value)
    if @addressable then
      @function.insn_store_relative(@ptr, @offset, value)
    else
      @function.insn_store(@value, value)
    end
  end

  # Emit code to get the value of this variable.  Returns a JIT::Value
  # that contains the variable's value.
  def get
    if @addressable then
      return @function.insn_load_relative(@ptr, @offset, JIT::Type::OBJECT)
    else
      return @value
    end
  end

  # Indicate that this variable needs to be addressable (that is, it
  # needs to be stored somewhere rather than in a pointer).  Variables
  # need to be addressable if they are accessed from inside a block.
  #
  # +ptr+:: a pointer to the address of a block of memory where
  # addressable variables are stored
  # +offset+:: the offset (in bytes) of the variable within the block
  #
  # TODO: It should be possible to keep variables in registers until the
  # block is called, then dump all local variables to addressable
  # locations when the block is called, but this is a future
  # optimization.
  def set_addressable(ptr, offset)
    raise "nil ptr" if ptr.nil?
    @addressable = true
    @ptr = ptr
    @offset = offset
  end

  # Create a new LocalVariable in an inner function that was created in
  # an outer function (e.g. when iterating).
  #
  # +function+:: the JIT::Function of the inner function
  # +name+:: the name of the variable as a Symbol
  # +ptr+:: a pointer to the address of a block of memory where
  # addressable variables are stored
  # +offset+:: the offset (in bytes) of the variable within the block
  def self.load(function, name, ptr, offset)
    var = self.new(function, name)
    var.set_addressable(ptr, offset)
    return var
  end
end

end # Ludicrous

