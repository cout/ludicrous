module Ludicrous

CompileOptionsMembers = Struct.new(
    :optimization_level,
    :precompile,
    :iterate_style,
    :dont_compile)

# Specifies the parameters used to compile a function or class
class CompileOptions < CompileOptionsMembers
  # Create a new CompileOptions object.
  #
  # Keyword arguments:
  # * precompile (true/false) - indicates that the method or class
  # should be compiled right away instead of the first time a method is
  # called (default=false)
  # * optimization_level (integer) - specifies the optimization level to
  # pass to libjit (default=2)
  # * iterate_style (:fast/:proc/:splat/nil) - indicates the iteration
  # style to use on 1.8 (default=nil, which is to use the most
  # conformant method available).  Ludicrous ignores this parameter on
  # YARV.
  # * dont_compile (true/false) - indicates that this class or method
  # should not be compiled.
  #
  # == Iteration methods
  #
  # === :fast
  #
  # Iterates using rb_iterate().
  #
  # The fastest way to iterate, but not 100% correct, because:
  #   yield *[[1, 2]]
  # should be yielded to us as:
  #   [1, 2]
  # but instead is yielded as:
  #   [[1, 2]]
  #
  # === :proc
  #
  # The next fastest way to iterate, using avalue instead of svalue (so it
  # may be faster for yield splat)
  #
  #
  # === :splat
  #
  # The slowest way to iterate, but matches ruby's behavior 100% for
  # most cases
  #
  # (one case that isn't exact - this method can't handle setting $1..$9
  # inside a block, but the user should not notice, because this is
  # disabled for now)
  def initialize(h = {})
    self.precompile = false
    self.optimization_level = 2
    self.iterate_style = nil
    self.dont_compile = false

    h.each do |k, v|
      self[k] = v
    end
  end
end

end # Ludicrous
