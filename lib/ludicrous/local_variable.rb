module Ludicrous

class LocalVariable
  def initialize(function, name)
    @function = function
    @name = name
    @addressable = false
    @value = @function.value(JIT::Type::OBJECT)
  end

  def init
    self.set(@function.const(JIT::Type::OBJECT, nil))
  end

  def set(value)
    if @addressable then
      @function.insn_store_relative(@ptr, @offset, value)
    else
      @function.insn_store(@value, value)
    end
  end

  def get
    if @addressable then
      return @function.insn_load_relative(@ptr, @offset, JIT::Type::OBJECT)
    else
      return @value
    end
  end

  def set_addressable(ptr, offset)
    raise "nil ptr" if ptr.nil?
    @addressable = true
    @ptr = ptr
    @offset = offset
  end

  def self.load(function, name, ptr, offset)
    var = self.new(function, name)
    var.set_addressable(ptr, offset)
    return var
  end
end

end # Ludicrous

