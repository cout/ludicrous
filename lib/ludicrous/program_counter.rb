module Ludicrous

class ProgramCounter
  attr_reader :offset

  def initialize
    @offset = 0
  end

  def advance(instruction_length)
    @offset += instruction_length
  end

  def reset()
    @offset = 0
  end
end

end # Ludicrous
