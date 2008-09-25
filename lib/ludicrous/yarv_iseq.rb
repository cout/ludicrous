require 'ludicrous/yarv_vm'

class RubyVM
  class InstructionSequence
    def ludicrous_compile(function, env)
      self.each do |instruction|
        # env.stack.sync_sp
        # function.debug_inspect_object instruction
        env.make_label
        env.pc.advance(instruction.length)
        instruction.ludicrous_compile(function, env)
        # env.stack.sync_sp
        # env.stack.debug_inspect
      end
    end
  end
end

