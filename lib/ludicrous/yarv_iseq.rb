require 'ludicrous/yarv_vm'
require 'internal/tag'

class RubyVM
  class InstructionSequence
    def ludicrous_compile(function, env)
      puts self.disasm

      if self.catch_table.size > 0 then
        self.ludicrous_compile_body_with_catch(function, env)
      else
        self.ludicrous_compile_body(function, env)
      end
    end

    def ludicrous_compile_body_with_catch(function, env)
      instructions = self.entries
      idx = 0

      env.sorted_catch_table.each do |catch_entry|
        while env.pc.offset < catch_entry.start do
          instruction = instructions[idx]
          ludicrous_compile_next_instruction(function, env, instruction)
          idx += 1
        end

        ludicrous_compile_catch_entry(function, env, catch_entry) do
          # TODO: I don't know if this should be < or <=.  If <, then
          # REDO fails to compile (because the LEAVE instruction at the
          # end is missed, so the stack isn't empty when it hits the
          # branch)
          while env.pc.offset <= catch_entry.end do
            instruction = instructions[idx]
            ludicrous_compile_next_instruction(function, env, instruction)
            idx += 1
          end
        end
      end

      while idx < instructions.length
        instruction = instructions[idx]
        ludicrous_compile_next_instruction(function, env, instruction)
        idx += 1
      end
    end

    CATCH_TYPE_TAG = Hash.new { |h, k|
      raise "No such catch type #{k}"
    }

    CATCH_TYPE_TAG.update({
      CATCH_TYPE_RESCUE => Tag::RAISE,
      CATCH_TYPE_BREAK  => Tag::BREAK,
      CATCH_TYPE_REDO   => Tag::REDO,
      CATCH_TYPE_NEXT   => Tag::NEXT,
      CATCH_TYPE_RETRY  => Tag::RETRY,
    })

    def ludicrous_compile_catch_entry(function, env, catch_entry, &block)
      catch_tag = function.const(
          JIT::Type::INT,
          CATCH_TYPE_TAG[catch_entry.type])
      zero = function.const(JIT::Type::INT, 0)

      state = env.with_tag_for(catch_entry, &block)

      case catch_entry.type
      when CATCH_TYPE_RESCUE
        function.if(state == zero) {
        }.elsif(state == catch_tag) {
          if catch_entry.sp != 0 then
            raise "Can't handle catch entry with sp=#{sp}"
          end

          tag = Ludicrous::VMTag.create(function)
          catch_state = env.with_tag(tag) do
            catch_entry_env = Ludicrous::YarvEnvironment.new(
                function,
                env.options,
                env.cbase,
                env.scope,
                catch_entry.iseq)
            catch_entry.iseq.ludicrous_compile(function, catch_entry_env)
          end

          # TODO: reset errinfo

          function.if(catch_state == zero) {
            env.branch(catch_entry.cont)
          }.elsif(catch_state == function.const(JIT::Type::INT, Tag::RETRY)) {
            env.branch_consume(catch_entry.start)
          }.else {
            function.rb_jump_tag(state)
          }.end

        }.else {
          function.rb_jump_tag(state)
        }.end

      when CATCH_TYPE_ENSURE
        raise "Unknown catch type 'ensure'"

      when CATCH_TYPE_RETRY
        # Retry is an interesting special case.  The retry block is
        # always surrounding a no-op, which is jumped to by a RESCUE
        # block.  We always handle the retry case in ludicrous by the
        # rescue block, above, so we don't need to (shouldn't try to)
        # handle it here.

      when CATCH_TYPE_BREAK, CATCH_TYPE_REDO, CATCH_TYPE_NEXT
        function.if(state == zero) {
        }.elsif(state == catch_tag) {
          env.branch(catch_entry.cont)
        }.else {
          function.rb_jump_tag(state)
        }.end
        
      end
    end

    def ludicrous_compile_body(function, env)
      self.each do |instruction|
        ludicrous_compile_next_instruction(function, env, instruction)
      end
    end

    def ludicrous_compile_next_instruction(function, env, instruction)
      # env.stack.sync_sp
      msg = "#{'%04d' % env.pc.offset} " +
            "#{'%x' % self.object_id} " +
            "#{instruction.inspect}"
      # puts msg
      function.debug_print_msg(msg)
      # function.debug_inspect_object instruction
      env.make_label
      env.pc.advance(instruction.length)
      instruction.ludicrous_compile(function, env)
      # env.stack.sync_sp
      # env.stack.debug_inspect
    end

    def ludicrous_compile_catch_table(function, env)
    end
  end
end

