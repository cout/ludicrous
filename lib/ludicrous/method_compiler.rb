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

