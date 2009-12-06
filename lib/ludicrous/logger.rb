module Ludicrous

# A logger that doesn't do any logging (the default logger).
class NullLogger
  def method_missing(*args)
  end
end

# By default, use the NullLogger.
@logger = NullLogger.new

class << self
  ##
  # A public accessor for the logger used by the jit compiler.
  attr_accessor :logger
end

end # Ludicrous

