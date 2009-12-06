# Require this file to get Ludicrous to compile itself

require 'ludicrous'

JIT::Value.go_plaid
JIT::Function.go_plaid

Node.go_plaid

Node.constants.each do |name|
  klass = Node.const_get(name)
  if Node === klass then
    klass.go_plaid
  end
end

Ludicrous::MethodCompiler.go_plaid

# TODO: This causes a cyclic include
# Ludicrous::Speed.go_plaid

MethodSig.go_plaid

Method.go_plaid
UnboundMethod.go_plaid

