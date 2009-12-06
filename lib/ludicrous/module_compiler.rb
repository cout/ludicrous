class Mutex
  ##
  # Never compile the Mutex module
  LUDICROUS_DONT_COMPILE = true
end

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

