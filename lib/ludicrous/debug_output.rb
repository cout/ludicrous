# Helper methods for emitting code to print values as a compiled
# function executes.

require 'ludicrous/native_functions'

module JIT

class Function
  # Emit a call to +printf(*args)+.
  def debug_printf(*args)
    rb_funcall($stdout, :printf, *args)
  end

  # Emit a call to +puts(obj)+.
  def debug_print_object(obj)
    rb_funcall($stdout, :puts, obj)
  end

  # Emit a call to +puts(obj.inspect)+.
  def debug_inspect_object(obj)
    insp = rb_funcall(obj, :inspect)
    debug_print_object(insp)
  end

  # Emit a call to +puts(uint)+, converting uint to a ruby type first.
  def debug_print_uint(uint)
    v = rb_uint2inum(uint)
    debug_print_object(v)
  end

  # Emit a call to +puts(ptr)+, converting ptr to a ruby string first.
  def debug_print_ptr(ptr)
    fmt = const(JIT::Type::OBJECT, '0x%x')
    v = rb_uint2inum(ptr)
    str = rb_funcall(fmt, :%, v)
    debug_print_object(str)
  end

  # Emit a call to +puts(msg)+.
  def debug_print_msg(msg)
    v = const(JIT::Type::OBJECT, msg)
    debug_print_object(v)
  end

  # Emit a call to +pp(node)+.
  def debug_print_node(node)
    require 'nodepp'
    debug_print_msg(PP.pp(node, ""))
  end

end # Function

end # JIT

