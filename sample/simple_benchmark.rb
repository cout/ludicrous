require "gcls"
require "benchmark"
require "getoptlong"
include Benchmark

class Symbol
  def <=>(rhs)
    self.to_s <=> rhs.to_s
  end
end

opts = GetoptLong.new(*[
    [ '--test', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--skip', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--jit', GetoptLong::NO_ARGUMENT ],
    [ '--factor', GetoptLong::REQUIRED_ARGUMENT ],
])

factor = 1

tests = {
  :ack => [
    "Ackermann function",
    :ack,
    proc { (factor * 300000).times { ack } }
  ],
  :array => [
    "Array access",
    :array_access,
    proc { (factor * 1000).times { array_access } }
  ],
  :fib => [
    "Fibonacci numbers",
    :fib,
    proc { (factor * 30).times { fib } }
  ],
  :hash1 => [
    "Hash access I",
    :hash_access_I,
    proc { (factor * 10000).times { hash_access_I } }
  ],
  :hash2 => [
    "Hash access II",
    :hash_access_II,
    proc { (factor * 5).times { hash_access_II } }
  ],
  :lists => [
    "Lists",
    :lists,
    proc { (factor * 3).times { for iter in 1..10; result = lists; end } }
  ],
  :nested_loop => [
    "Nested loop",
    :nested_loop,
    proc { (factor * 5).times { nested_loop } }
  ],
  :sieve => [
    "Sieve of Eratosthenes",
    :sieve_of_eratosthenes,
    proc { (factor * 10).times{ sieve_of_eratosthenes } }
  ],
  :word_freq => [
    "Word Frequency",
    :word_frequency,
    proc { (factor * 1000).times { word_frequency } }
  ],
  :gcd_iter => [
    "GCD (iterative)",
    :gcd_iter,
    proc { (factor * 10000).times{ gcd_iter } }
  ],
  :gcd_recur => [
    "GCD (recursive)",
    :gcd_recur,
    proc { (factor * 2000).times{ gcd_recur } }
  ],
}

def run_benchmark(x, label, p)
  begin
    GC.start
    x.report(label, &p)
  rescue
    puts "#{$!} (#{$!.backtrace[0]})"
  end
end

jit = false

opts.each do |opt, arg|
  case opt
  when '--test'
    test_names = arg.split(',').map { |name| name.intern }
    test_names.each do |test_name|
      if not tests.include?(test_name) then
        $stderr.puts "No such test #{test_name}"
        exit 1
      end
    end
    tests.delete_if { |name, test_info| !test_names.include?(name) }
  when '--skip'
    test_names = arg.split(',').map { |name| name.intern }
    test_names.each do |test_name|
      if not tests.include?(test_name) then
        $stderr.puts "No such test #{test_name}"
        exit 1
      end
    end
    tests.delete_if { |name, test_info| test_names.include?(name) }
  when '--jit'
    jit = true
  when '--factor'
    factor = Integer(arg)
  end
end

if jit then
  require "ludicrous"
  tests.each do |test_name, test_info|
    name = test_info[1]
    Object.ludicrous_compile_method(name)
  end
end

if tests.size == 0 then
  $stderr.puts "No matching tests found"
  exit 1
end

widths = tests.map { |name, test_info| test_info[0].length }
max_width = widths.max

bm(max_width) do |x|
  tests.sort.each do |name, test_info|
    label = test_info[0].to_s
    p = test_info[2]
    run_benchmark(x, label, p)
  end
end
