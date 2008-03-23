# gcls.rb
# Ackermann function
def ack(m=0, n=0)
   if m == 0 then
     n + 1
   elsif n == 0 then
     ack(m - 1, 1)
   else
     ack(m - 1, ack(m, n - 1))
   end
end

# Array access
def array_access(n=1)
   x = Array.new(n)
   y = Array.new(n, 0)

   for i in 0...n
      x[i] = i + 1
   end

   for k in 0..999
      (n-1).step(0,-1) do |i|
         y[i] = y.at(i) + x.at(i)
      end
   end
end

# Fibonacci numbers
def fib(n=20)
   if n < 2 then
    1
   else
    fib(n-2) + fib(n-1)
   end
end
   
# Hash Access I
def hash_access_I(n=20)
   hash = {}
   for i in 1..n
      hash['%x' % i] = 1
   end

   c = 0
   n.downto 1 do |i|
      c += 1 if hash.has_key? i.to_s
   end
end

# Hash Access II
def hash_access_II(n=20)
   hash1 = {}
   for i in 0 .. 9999
      hash1["foo_" << i.to_s] = i
   end

   hash2 = Hash.new(0)
   n.times do
      for k in hash1.keys
         hash2[k] += hash1[k]
      end
   end
end   

# lists
SIZE = 10000
def lists
   li1 = (1..SIZE).to_a
   li2 = li1.dup
   li3 = Array.new

   while (not li2.empty?)
      li3.push(li2.shift)
   end

   while (not li3.empty?)
      li2.push(li3.pop)
   end

   li1.reverse!

   if li1[0] != SIZE then
      p "not SIZE"
     return(0)
   end

   if li1 != li2 then
     return(0)
   end

   return(li1.length)
end

def nested_loop(n = 10)
   x = 0
   n.times do
      n.times do
         n.times do
            n.times do
               n.times do
                  n.times do
                  x += 1
                  end
               end
            end
         end
      end
   end
end

def sieve_of_eratosthenes(n=20)
   count = i = j = 0
   flags0 = Array.new(8192,1)

   n.times do |i|
      count = 0
      flags = flags0.dup
      for i in 2 .. 8192
         next unless flags[i]
         (i+i).step(8192, i) do |j|
            flags[j] = nil
         end
         count = count + 1
      end
   end
end

def statistical_moments
   sum = 0.0
   nums = []
   num = nil

   for line in STDIN.readlines()
     num = Float(line)
     nums << num
     sum += num
   end

   n = nums.length()
   mean = sum/n;
   deviation = 0.0
   average_deviation = 0.0
   standard_deviation = 0.0
   variance = 0.0
   skew = 0.0
   kurtosis = 0.0
    
   for num in nums
     deviation = num - mean
     average_deviation += deviation.abs()
     variance += deviation**2;
     skew += deviation**3;
     kurtosis += deviation**4
   end

   average_deviation /= n
   variance /= (n - 1)
   standard_deviation = Math.sqrt(variance)

   if (variance > 0.0)
     skew /= (n * variance * standard_deviation)
     kurtosis = kurtosis/(n * variance * variance) - 3.0
   end

   nums.sort()
   mid = n / 2
    
   if (n % 2) == 0
     median = (nums.at(mid) + nums.at(mid-1))/2
   else
     median = nums.at(mid)
   end
end

def word_frequency
   data = "While the word Machiavellian suggests cunning, duplicity,
or bad faith, it would be unfair to equate the word with the man. Old
Nicolwas actually a devout and principled man, who had profound
insight into human nature and the politics of his time. Far more
worthy of the pejorative implication is Cesare Borgia, the incestuous
and multi-homicidal pope who was the inspiration for The Prince. You
too may ponder the question that preoccupied Machiavelli: can a
government stay in power if it practices the morality that it preaches
to its people?"
   freq = Hash.new(0)
   for word in data.downcase.tr_s('^A-Za-z',' ').split(' ')
      freq[word] += 1
   end
   freq.delete("")
   lines = Array.new
   freq.each{|w,c| lines << sprintf("%7d\t%s\n", c, w) }
end


def gcd_recur(x=1000, y=1005)
  if x == y
    return x
  elsif x < y
    return gcd_recur(x, y - x)
  else
    return gcd_recur(x - y, y)
  end
end

def gcd_iter(x=1000, y=1005)
  while x != y do
    if x < y
      y -= x
    else
      x -= y
    end
  end
  return x
end

