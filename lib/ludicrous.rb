# The Ludicrous JIT compiler.
#
# To use it, include the Ludicrous::JITCompiled module in your class or
# module, or call Module#ludicrous_compile_method to compile an
# individual method.

require 'thread'
require 'internal/node'
require 'internal/node/to_a'
require 'internal/method/signature'
require 'internal/noex'

# TODO: The only reason this file is required here is that for now, it
# must be required before ludicrous.so.
require 'internal/thread'

require 'jit'
require 'jit/value'
require 'jit/struct'
require 'jit/function'

require 'ludicrous_ext'

require 'ludicrous/value_conversions'
require 'ludicrous/native_functions'
require 'ludicrous/method_nodes'
require 'ludicrous/logger'
require 'ludicrous/local_variable'
require 'ludicrous/scope'
require 'ludicrous/environment'
require 'ludicrous/compile_options'
require 'ludicrous/debug_output'
require 'ludicrous/toplevel'
require 'ludicrous/stubs'
require 'ludicrous/module_compiler'
require 'ludicrous/method_compiler'
require 'ludicrous/speed'

require 'ludicrous/yarv_vm'

if defined?(RubyVM) then
# >= 1.9
require 'ludicrous/yarv_instructions'
require 'ludicrous/yarv_iseq'
else
# <= 1.8
require 'ludicrous/eval_nodes'
end

