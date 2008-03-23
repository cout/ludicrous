module Ludicrous

OptionsMembers = Struct.new(
    :optimization_level,
    :precompile,
    :iterate_style)

class Options < OptionsMembers
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
