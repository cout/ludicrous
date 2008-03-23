module Ludicrous

class NullLogger
  def method_missing(*args)
  end
end

@logger = NullLogger.new

class << self
  attr_accessor :logger
end

end # Ludicrous

