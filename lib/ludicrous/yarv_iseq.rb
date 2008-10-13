require 'ludicrous/yarv_vm'
require 'internal/tag'

class RubyVM
  class InstructionSequence
    def ludicrous_compile(function, env)
      if self.catch_table.size > 0 then
        self.ludicrous_compile_body_with_catch(function, env)
      else
        self.ludicrous_compile_body(function, env)
      end
    end

    # TODO: This method belongs elsewhere
    def push_tag(function, env)
      tag = Ludicrous::VMTag.create(function)
      tag.tag = function.const(JIT::Type::INT, 0)
      tag.prev = function.ruby_current_thread_tag()
      function.ruby_set_current_thread_tag(tag.ptr)
      return tag
    end

    def pop_tag(function, env, tag)
      function.ruby_set_current_thread_tag(tag.prev)
    end

    # TODO: This method belongs elsewhere
    def exec_tag(function, env)
      # TODO: _setjmp may or may not be right for this platform
      jmp_buf = function.ruby_current_thread_jmp_buf()
      return function._setjmp(jmp_buf)
    end

    def ludicrous_compile_body_with_catch(function, env)
      zero = function.const(JIT::Type::INT, 0)
      tag = push_tag(function, env)
      state = exec_tag(function, env)
      pop_tag(function, env, tag)
      function.if(state == zero) {
        self.ludicrous_compile_body(function, env)
      }.else {
        # TODO: ludicrous_compile_catch_table
        function.rb_jump_tag(state)
      }.end
    end

    def ludicrous_compile_body(function, env)
      self.each do |instruction|
        # env.stack.sync_sp
        function.debug_inspect_object instruction
        env.make_label
        env.pc.advance(instruction.length)
        instruction.ludicrous_compile(function, env)
        # env.stack.sync_sp
        # env.stack.debug_inspect
      end
    end

    def ludicrous_compile_catch_table(function, env)
      self.catch_table.each do |entry|
        case entry.type
        when CATCH_TYPE_RESCUE
          raise "Unknown catch type 'rescue'"
        when CATCH_TYPE_ENSURE
          raise "Unknown catch type 'ensure'"
        when CATCH_TYPE_RETRY
          raise "Unknown catch type 'retry'"
        when CATCH_TYPE_BREAK
          raise "Unknown catch type 'break'"
        when CATCH_TYPE_REDO
          raise "Unknown catch type 'redo'"
        when CATCH_TYPE_NEXT
          raise "Unknown catch type 'next'"
        end
      end
    end
  end
end

