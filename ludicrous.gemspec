require 'enumerator'

spec = Gem::Specification.new do |s|
  s.name = 'ludicrous'
  s.version = '0.0.1'
  s.summary = 'A just-in-time (JIT) compiler for MRI and YARV'
  s.homepage = 'http://rubystuff.org/ludicrous/'
  s.rubyforge_project = 'ludicrous'
  s.author = 'Paul Brannan'
  s.email = 'curlypaul924@gmail.com'

  s.add_dependency 'ruby-internal'    => '>= 0.7.1'
  s.add_dependency 'ruby-libjit'      => '>= 0.2.2'
  s.add_dependency 'ruby-decompiler'  => '>= 0.0.2'

  s.description = <<-END
Ludicrous is a just-in-time (JIT) compiler that works with the Ruby 1.8
and 1.9 series interpreters.  It works by walking the AST or bytecode
and converting it into machine code the first time a method is called.
It is thus naive, but can produce amazing results.  Which
methods/classes get compiled can easily be controlled with just a few
lines of code.
  END


  patterns = [
    'COPYING',
    'LGPL',
    'LICENSE',
    'README',
    'bin/ludicrous',
    'lib/**/*.rb',
    'lib/*.rb',
    'ext/*.rb',
    'ext/*.c',
    'ext/*.h',
    'sample/*.rb',
    'test/*.rb',
  ]

  s.files = patterns.collect { |p| Dir.glob(p) }.flatten

  s.test_files = Dir.glob('test/test_*.rb')

  s.extensions = 'ext/extconf.rb'

  s.executables = 'ludicrous'

  s.has_rdoc = true
end

