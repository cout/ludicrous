class VM
  class InstructionSequence
    def ludicrous_compile(function, env)
      self.each do |instruction|
        env.make_label
        instruction.ludicrous_compile(function, env)
        env.advance(instruction.length)
      end
    end
  end
end

