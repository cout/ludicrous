module Ludicrous

# A simple program counter, used by the YARV bytecode compiler.
class ProgramCounter
  # Return the current value of the program counter.
  attr_reader :offset

  # Create a new ProgramCounter with value 0.
  def initialize
    @offset = 0
  end

  # Advance the program counter by +instruction_length+ units.
  #
  # +instruction_length+:: the amount to increment the program counter
  # by.
  def advance(instruction_length)
    @offset += instruction_length
  end

  # Reset the program counter to 0.
  def reset()
    @offset = 0
  end
end

end # Ludicrous
