module Ludicrous

CompileOptionsMembers = Struct.new(
    :optimization_level,
    :precompile,
    :iterate_style)

class CompileOptions < CompileOptionsMembers
  def initialize(h = {})
    self.precompile = false
    self.optimization_level = 2
    self.iterate_style = nil

    h.each do |k, v|
      self[k] = v
    end
  end
end

end # Ludicrous
