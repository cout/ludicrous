require 'ludicrous/native_functions'

module JIT

class Function
  def debug_print_object(obj)
    rb_funcall($stdout, :puts, obj)
  end

  def debug_inspect_object(obj)
    insp = rb_funcall(obj, :inspect)
    debug_print_object(insp)
  end

  def debug_print_uint(uint)
    v = rb_uint2inum(uint)
    debug_print_object(v)
  end

  def debug_print_ptr(ptr)
    fmt = const(JIT::Type::OBJECT, '0x%x')
    v = rb_uint2inum(ptr)
    str = rb_funcall(fmt, :%, v)
    debug_print_object(str)
  end

  def debug_print_msg(msg)
    v = const(JIT::Type::OBJECT, msg)
    debug_print_object(v)
  end

  def debug_print_node(node)
    require 'nodepp'
    debug_print_msg(PP.pp(node, ""))
  end

end # Function

end # JIT

