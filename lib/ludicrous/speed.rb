require 'ludicrous/stubs'

module Ludicrous

##
# Allow the user to write:
#
#   module Foo
#     include Ludicrous::Speed
#   end
Speed = JITCompiled

end # module Ludicrous

