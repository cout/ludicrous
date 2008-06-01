class VM
  class InstructionSequence
    def ludicrous_compile(function, env)
      self.each do |instruction|
        instruction.ludicrous_compile(function, env)
      end
    end
  end
end

