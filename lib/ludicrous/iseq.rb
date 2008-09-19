class VM
  class InstructionSequence
    def ludicrous_compile(function, env)
      self.each do |instruction|
        # env.stack.sync_sp
        # function.debug_inspect_object instruction
        env.make_label
        instruction.ludicrous_compile(function, env)
        env.pc.advance(instruction.length)
        # env.stack.sync_sp
        # env.stack.debug_inspect
      end
    end
  end
end

