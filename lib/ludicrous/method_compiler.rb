# Helpers for compiling individual Method objects.

class Method
  # Compiles the given Method.
  #
  # Returns a C function that can be called in lieu of calling the
  # Method.
  #
  # +options+:: a CompileOptions object with parameters indicating how
  # the method should be compiled
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
  # Compiles the given UnboundMethod.
  #
  # Returns a C function that can be called in lieu of calling the
  # UnboundMethod.
  #
  # +options+:: a CompileOptions object with parameters indicating how
  # the method should be compiled
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

