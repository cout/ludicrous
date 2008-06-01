require 'test/unit/autorunner'
require 'test/unit/testcase'
require 'ludicrous'

class TestLudicrousSpeed < Test::Unit::TestCase
  def test_existing_method
    c = Class.new { def foo; 42; end }
    c.class_eval { include Ludicrous::Speed }
    assert_equal 42, c.new.foo
    assert_equal Node::CFUNC, c.instance_method(:foo).body.class
  end

  def test_dynamic_add_method
    c = Class.new { include Ludicrous::Speed }
    c.class_eval { def foo; 42; end }
    assert_equal 42, c.new.foo
    assert_equal Node::CFUNC, c.instance_method(:foo).body.class
  end
end

if __FILE__ == $0 then
  exit Test::Unit::AutoRunner.run #(true)
end

