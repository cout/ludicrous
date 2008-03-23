require 'jit'
require 'ludicrous'
require 'test/unit/autorunner'

RUBY_SOURCE_DIR='/home/cout/download/ruby/ruby-1.8.6/test/ruby'

exclude_files = [
  'marshaltestlib.rb',
  'beginmainend.rb',
  'endblockwarn.rb',
]

$: << RUBY_SOURCE_DIR
Dir["#{RUBY_SOURCE_DIR}/*.rb"].each do |file|
  next if exclude_files.include?(File.basename(file))
  puts "Requiring #{file}"
  require file
end

use_jit = true
if ARGV.include?('--without-jit') then
  use_jit = false
  ARGV.delete('--without-jit')
end

module MarshalTestLib
  # These tests fail when nodewrap is loaded
  remove_method :test_anonymous
  remove_method :test_singleton
end

ObjectSpace.each_object(Class) do |klass|
  next if not klass < Test::Unit::TestCase

  # TODO: can't handle lambda yet
  # next if klass == TestProc

  klass.instance_methods(false).sort.each do |name|
    next if name !~ /^test_/
    full_name = "#{klass}##{name}"

    if use_jit then
      klass.instance_eval { include Ludicrous::Speed }
    end
  end
end

if __FILE__ == $0 then
  exit Test::Unit::AutoRunner.run #(true)
end

