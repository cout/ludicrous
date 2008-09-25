require 'thread'
require 'internal/node'
require 'internal/node/to_a'
require 'internal/method/signature'
require 'internal/noex'

require 'jit'
require 'jit/value'
require 'jit/struct'
require 'jit/function'

require 'ludicrous.so'

require 'ludicrous/value_conversions'
require 'ludicrous/native_functions'
require 'ludicrous/method_nodes'
require 'ludicrous/logger'
require 'ludicrous/local_variable'
require 'ludicrous/scope'
require 'ludicrous/environment'
require 'ludicrous/compile_options'
require 'ludicrous/debug_output'
require 'ludicrous/toplevel'

require 'ludicrous/yarv_vm'

if defined?(RubyVM) then
# >= 1.9
require 'ludicrous/yarv_instructions'
require 'ludicrous/yarv_iseq'
else
# <= 1.8
require 'ludicrous/eval_nodes'
end

class Mutex
  LUDICROUS_DONT_COMPILE = true
end

module Ludicrous

module JITCompiled
  def self.jit_compile_stub(klass, method, name, orig_name)
    tmp_name = "ludicrous__tmp__#{name}".intern

    success = proc { |f|
      # Alias the method so we won't get a warning from the
      # interpreter
      klass.__send__(:alias_method, tmp_name, name)

      # Replace the method with the compiled version
      # TODO: public/private/protected?
      klass.define_jit_method(name, f)
      return true
    }

    failure = proc { |exc|
      # raise # TODO: remove
      # Revert to the original (non-stub) method
      klass.__send__(:alias_method, tmp_name, name)
      klass.__send__(:alias_method, name, orig_name)
      return false
    }

    jit_compile_method(klass, name, method, success, failure)

    # Remove the aliased methods
    klass.__send__(:remove_method, tmp_name)
    klass.__send__(:remove_method, orig_name)
    klass.__send__(:remove_const, "HAVE_LUDICROUS_JIT_STUB__#{name.intern.object_id}")
  end

  def self.jit_compile_method(
        klass,
        name,
        method = klass.instance_method(name),
        success = proc { },
        failure = proc { })

    successful = false
    f = nil

    begin
      Ludicrous.logger.info "Compiling #{klass}##{name}..."
      if klass.const_defined?(:LUDICROUS_OPTIMIZATION_LEVEL) and
         opt = klass.const_get(:LUDICROUS_OPTIMIZATION_LEVEL)
        f = method.ludicrous_compile(opt)
      else
        f = method.ludicrous_compile
      end

      successful = true

    rescue
      Ludicrous.logger.error "#{klass}##{name} failed: #{$!.class}: #{$!} (#{$!.backtrace[0]})"
      failure.call($!)
    end

    if successful then
      Ludicrous.logger.info "#{klass}##{name} compiled"
      success.call(f)
    end
  end

  def self.compile_proc(klass, method, name, orig_name)
    m = Mutex.new
    compile_proc = proc {
      compiled = false
      if m.try_lock then
        begin
          compiled = Ludicrous::JITCompiled.jit_compile_stub(klass, method, name, orig_name)
        ensure
          m.unlock
        end
      end
      compiled
    }
    return compile_proc
  end

  def self.jit_stub(klass, name, orig_name, method)
    compile_proc = self.compile_proc(klass, method, name, orig_name)

    # TODO: the stub should have the same arity as the original
    # TODO: the stub should have the same access protection as the original
    signature = JIT::Type::RUBY_VARARG_SIGNATURE
    JIT::Context.build do |context|
      function = JIT::Function.compile(context, signature) do |f|
        argc = f.get_param(0)
        argv = f.get_param(1)
        recv = f.get_param(2)

        # Store the args...
        args = f.rb_ary_new4(argc, argv)

        # ... and the passed block for later.
        passed_block = f.value(JIT::Type::OBJECT)
        f.if(f.rb_block_given_p()) {
          passed_block.store f.rb_block_proc()
        }.else {
          passed_block.store f.const(JIT::Type::OBJECT, nil)
        }.end

        unbound_method = f.value(JIT::Type::OBJECT)

        # Check to see if this is a module function
        f.if(f.rb_obj_is_kind_of(recv, f.const(JIT::Type::OBJECT, klass))) {
          # If it wasn't, go ahead and compile it
          p = f.const(JIT::Type::OBJECT, compile_proc)

          f.if(f.rb_funcall(p, :call)) {
            # If compilation was successful, then we'll call the
            # compiled method
            unbound_method.store f.rb_funcall(
                f.const(JIT::Type::OBJECT, klass),
                :instance_method,
                f.const(JIT::Type::OBJECT, name))
          }.else {
            # Otherwise we'll call the uncompiled method
            unbound_method.store f.const(JIT::Type::OBJECT, method)
          }.end
        }.else {
          # This is a module function, so fix the module to not have the
          # stub (TODO: perhaps we should just compile the method?)
          mid = f.const(JIT::Type::ID, name.intern)
          sc = f.rb_singleton_class(recv)
          f.rb_add_method(
              sc,
              f.const(JIT::Type::ID, name.intern),
              f.unwrap_node(f.const(JIT::Type::OBJECT, method.body)),
              f.const(JIT::Type::INT, Noex::PUBLIC))

          # And prepare to call the uncompiled method
          unbound_method.store f.rb_funcall(
              sc,
              :instance_method,
              f.const(JIT::Type::OBJECT, name))
        }.end

        # Bind the method we want to call to the receiver
        bound_method = f.rb_funcall(
            unbound_method,
            :bind,
            recv)

        # And call the receiver, passing the given block
        f.insn_return f.block_pass_fcall(
            bound_method,
            f.const(JIT::Type::ID, :call),
            args,
            passed_block)

        # puts f.dump
      end
      # puts "done"
    end
  end

  def self.install_jit_stub(klass, name)
    # Don't install a stub for a stub
    return if name =~ /^ludicrous__orig_tmp__/
    return if name =~ /^ludicrous__stub_tmp__/
    return if name =~ /^ludicrous__tmp__/

    return if klass.const_defined?("HAVE_LUDICROUS_JIT_STUB__#{name.intern.object_id}")

    if klass.ludicrous_dont_compile then
      Ludicrous.logger.info("Not compiling #{klass}")
      return
    end

    begin
      method = klass.instance_method(name)
    rescue NameError
      # TODO: This is a hack
      # How we got here is that the derived class's method added called
      # the original method added, which called install_jit_stub for the
      # base class rather than for the derived class.  We need a better
      # solution than just capturing NameError, but this works for now.
      return
    end

    # Don't try to compile C functions or stubs, or methods for which we
    # aren't likely to see a speed improvement
    # TODO: For some reason we often try to compile jit stubs right
    # after they are installed
    body = method.body
    if Node::CFUNC === body or
       Node::IVAR === body or
       Node::ATTRSET === body then
      Ludicrous.logger.info "Not compiling #{body.class} #{klass}##{name}"
      return
    end

    Ludicrous.logger.info "Installing JIT stub for #{klass}##{name}..."
    tmp_name = "ludicrous__orig_tmp__#{name}".intern
    klass.instance_eval do
      alias_method tmp_name, name
      begin
        stub = Ludicrous::JITCompiled.jit_stub(klass, name, tmp_name, method)
        klass.define_jit_method(name, stub)
        klass.const_set("HAVE_LUDICROUS_JIT_STUB__#{name.intern.object_id}", true)
      rescue
        Ludicrous.logger.error "#{klass}##{name} failed: #{$!.class}: #{$!} (#{$!.backtrace[0]})"
      end
    end
  end

  def self.append_features(mod)
    if mod.ludicrous_dont_compile then
      Ludicrous.logger.info("Not compiling #{mod}")
      return
    end

    # TODO: not sure if this is necessary, but it can't hurt...
    if mod.instance_eval { defined?(@LUDICROUS_FEATURES_APPENDED) } then
      Ludicrous.logger.info("#{mod} is already JIT-compiled")
      return
    end
    mod.instance_eval { @LUDICROUS_FEATURES_APPENDED = true }

    if not JITCompiled === mod and not JITCompiled == mod then
      # Allows us to JIT-compile the JITCompiled class
      super
    end

    # TODO: We can't compile these right now
    # return if mod == UnboundMethod
    # return if mod == Node::SCOPE
    # return if mod == Node
    # return if mod == MethodSig::Argument

    if mod.const_defined?(:LUDICROUS_PRECOMPILED) and
       mod.const_get(:LUDICROUS_PRECOMPILED) then
      jit_precompile_all_instance_methods(mod)
    else
      install_jit_stubs_for_all_instance_methods(mod)
    end

    install_method_added_jit_hook(mod)
  end

  def self.jit_precompile_all_instance_methods(mod)
    if mod.ludicrous_dont_compile then
      Ludicrous.logger.info("Not compiling #{mod}")
      return
    end

    instance_methods = mod.public_instance_methods(false) + \
      mod.protected_instance_methods(false) + \
      mod.private_instance_methods(false)
    instance_methods.each do |name|
      jit_compile_method(mod, name)
    end
  end

  def self.install_jit_stubs_for_all_instance_methods(mod)
    if mod.ludicrous_dont_compile then
      Ludicrous.logger.info("Not compiling #{mod}")
      return
    end

    instance_methods = mod.public_instance_methods(false) + \
      mod.protected_instance_methods(false) + \
      mod.private_instance_methods(false)
    instance_methods.each do |name|
      install_jit_stub(mod, name)
    end
  end

  def self.install_method_added_jit_hook(mod)
    if mod.ludicrous_dont_compile then
      Ludicrous.logger.info("Not compiling #{mod}")
      return
    end

    Ludicrous.logger.info "Installing method_added hook for #{mod}"
    mod_singleton_class = class << mod; self; end
    mod_singleton_class.instance_eval do
      orig_method_added = method(:method_added)
      define_method(:method_added) { |name|
        orig_method_added.call(name)
        break if self != mod
        Ludicrous::JITCompiled.install_jit_stub(mod, name.to_s)
      }
    end
  end
end

Speed = JITCompiled

end # module Ludicrous

class Module
  def ludicrous_compile(options = Ludicrous::CompileOptions.new)
    return if defined?(@LUDICROUS_FEATURES_APPENDED)

    module_has_options = self.const_defined?(:LUDICROUS_OPTIONS)
    if not module_has_options then
      self.const_set(:LUDICROUS_OPTIONS, options)
    end

    Ludicrous.logger.info("including Ludicrous::Speed for #{self}")
    include Ludicrous::Speed
  end

  alias_method :go_plaid, :ludicrous_compile

  def ludicrous_compile_method(name)
    Ludicrous::Speed.jit_compile_method(self, name)
  end

  def ludicrous_dont_compile
    return (self.const_defined?(:LUDICROUS_DONT_COMPILE) or
       (self.const_defined?(:LUDICROUS_OPTIONS) and
       self::LUDICROUS_OPTIONS.dont_compile))
  end
end

class Method
  def ludicrous_compile(options = Ludicrous::CompileOptions.new)
    if options.dont_compile then
      Ludicrous.logger.info("Not compiling #{self}")
      return
    end

    return self.body.ludicrous_compile_into_function(
        self.attached_class || self.origin_class,
        options)
  end
end

class UnboundMethod
  def ludicrous_compile(options = Ludicrous::CompileOptions.new)
    if options.dont_compile then
      Ludicrous.logger.info("Not compiling #{self}")
      return
    end

    return self.body.ludicrous_compile_into_function(
        self.origin_class,
        options)
  end
end

if __FILE__ == $0 then

  require 'nodepp'

def foo(n=20)
  x = (a, b = 1)
  p a, b
  return x
end   

m = method(:foo)
# pp m.body
f = m.ludicrous_compile
puts "Compiled"
p f.apply(self)
# hash_access_II()

end
