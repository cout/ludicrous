require 'test/unit/autorunner'

require 'rubygems'
gem 'bfts'

$:.each do |dir|
  if dir =~ /bfts.*lib$/ then
    $: << File.expand_path(File.join(dir, '..'))
  end
end

tests = {
  'test_array'       => :TestArray,
  'test_comparable'  => :TestComparable,
  'test_exception'   => :TestException,
  'test_false_class' => :TestFalseClass,
  'test_file_test'   => :TestFileTest,
  'test_hash'        => :TestHash,
  'test_nil_class'   => :TestNilClass,
  'test_range'       => :TestRange,
  'test_string'      => :TestString,
  'test_struct'      => :TestStruct,
  'test_time'        => :TestTime,
  'test_true_class'  => :TestTrueClass,
}

# These tests fail without JIT, so we shouldn't expect them to pass with
# JIT
known_to_fail = [
  'TestFileTest#test_class_blockdev_eh',
  'TestFileTest#test_class_chardev_eh',
  'TestFileTest#test_class_exist_eh',
  'TestFileTest#test_class_exists_eh',
  'TestFileTest#test_class_file_eh',
  'TestFileTest#test_class_setuid_eh',
  'TestFileTest#test_class_size',
  'TestFileTest#test_class_size_eh',
  'TestFileTest#test_class_symlink_eh',
  'TestFileTest#test_class_zero_eh',
  'TestString#test_inspect',
  'TestTime#test_class_now',
  'TestTime#test_initialize',
  'TestTime#test_inspect',
  'TestTime#test_to_s',
]

use_jit = true
if ARGV.include?('--without-jit') then
  use_jit = false
  ARGV.delete('--without-jit')
end

if use_jit then
  require 'ludicrous'

  require 'logger'
  Ludicrous.logger = Logger.new(STDERR)
end

tests.each do |feature, klass_name|
  require feature
  klass = Object.const_get(klass_name)
  klass.instance_methods(false).sort.each do |name|
    full_name = "#{klass}##{name}"
    if known_to_fail.include?(full_name) then
      klass.instance_eval { remove_method(name) }
      next
    end
  end

  if use_jit then
    klass.instance_eval { include Ludicrous::Speed }
  end
end

if __FILE__ == $0 then
  exit Test::Unit::AutoRunner.run #(true)
end

