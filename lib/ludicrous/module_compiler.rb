# Adds methods to the Module class for compiling individual modules or
# methods in a module.

require 'ludicrous/stubs'
require 'ludicrous/compile_options'

class Mutex
  ##
  # Never compile the Mutex module
  LUDICROUS_DONT_COMPILE = true
end

class Module
  # Indicates that the given module should be JIT compiled.
  #
  # Installs stubs so that:
  # * Any method in the module will be compiled the first time it is
  # called
  # * Any new methods defined after this function is called will have
  # stubs installed once the method has been defined
  #
  # If options.precompile is set, all the methods in the module will be
  # compiled right away rather than delaying compilation until the
  # method is called.
  #
  # +options+:: a CompileOptions object with parameters indicating how
  # the methods in this module should be compiled
  def ludicrous_compile(options = Ludicrous::CompileOptions.new)
    return if defined?(@LUDICROUS_FEATURES_APPENDED)

    module_has_options = self.const_defined?(:LUDICROUS_OPTIONS)
    if not module_has_options then
      self.const_set(:LUDICROUS_OPTIONS, options)
    end

    Ludicrous.logger.info("including Ludicrous::Speed for #{self}")
    include Ludicrous::Speed
  end

  # Allows the user to write:
  #
  #   module.go_plaid()
  #
  # to compile a module.
  alias_method :go_plaid, :ludicrous_compile

  # Compile the instance method with the given name right away.
  #
  # TODO: This method is asymmetric with #ludicrous_compile and is
  # likely to change in the future.
  #
  # +name+ a Symbol indicating the name of the method to compile
  def ludicrous_compile_method(name)
    Ludicrous::Speed.jit_compile_method(self, name)
  end

  # Returns true if this module should not be compiled, false otherwise.
  def ludicrous_dont_compile
    if self.const_defined?(:LUDICROUS_DONT_COMPILE) then
      return false
    end

    if self.const_defined?(:LUDICROUS_OPTIONS) then
      return self::LUDICROUS_OPTIONS.dont_compile)
    end

    return false
  end

  # Returns true if the given method in this module should not be
  # compiled, false otherwise.
  #
  # +method+:: the name of the method to check (Symbol)
  def ludicrous_dont_compile_method(method)
    if ludicrous_dont_compile() then
      return true
    end

    if self.const_defined?(:LUDICROUS_DONT_COMPILE_METHODS) then
      return self::LUDICROUS_DONT_COMPILE_METHODS.include?(method)
    end

    if self.const_defined?(:LUDICROUS_OPTIONS) then
      return self::LUDICROUS_OPTIONS.exclude_methods.include?(method)
    end

    return false
  end
end

