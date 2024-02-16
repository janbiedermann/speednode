# frozen_string_literal: true

require 'securerandom'
require 'date'
require 'test_helper'

class SpeednodeTest < Minitest::Test

  def test_types
    context = ExecJS.compile('')
    assert_equal 2, context.eval('2')
    assert_equal "two", context.eval('"two"')
    assert_equal 2.1, context.eval('2.1')
    assert_equal true, context.eval('true')
    assert_equal false, context.eval('false')
    assert_nil context.eval('null')
    assert_nil context.eval('undefined')
  end

  def test_array
    context = ExecJS.compile('')
    assert_equal [1,"two"], context.eval('[1,"two"]')
  end

  def test_object
    context = ExecJS.compile('')
    # remember JavaScript is quirky {"1" : 1} magically turns to {1: 1} cause magic
    assert_equal({"1" => 2, "two" => "two"}, context.eval('var a={"1" : 2, "two" : "two"}; a'))
  end

  def test_it_returns_program_error
    context = ExecJS.compile('')
    exp = nil

    begin
      context.eval('var foo=function(){boom;}; foo()')
    rescue => e
      exp = e
    end

    assert_equal ExecJS::ProgramError, exp.class

    assert_match(/boom/, exp.message)
    assert_match(/foo/, exp.backtrace[0] + exp.backtrace[1]) # node 18 changed formatting

    # context should not be dead
    assert_equal 2, context.eval('1+1')
  end

  def test_it_can_automatically_time_out_context
    # 2 millisecs is a very short timeout but we don't want test running forever
    context = ExecJS.compile('', timeout: 50)
    assert_raises ExecJS::ProgramError do
      context.eval('while(true){}')
    end
  end

  def test_it_handles_malformed_js
    context = ExecJS.compile('')
    assert_raises ExecJS::RuntimeError do
      context.eval('I am not JavaScript {')
    end
  end

  # def test_it_handles_malformed_js_with_backtrace
  #   context = ExecJS.compile('')
  #   assert_raises ExecJS::RuntimeError do
  #     begin
  #       context.eval("var i;\ni=2;\nI am not JavaScript {")
  #     rescue => e
  #       # I <parse error> am not
  #       assert_match(/\(execjs\):3/, e.backtrace.join('\n'))
  #       raise e
  #     end
  #   end
  # end

  def test_it_remembers_stuff_in_context
    context = ExecJS.compile('')
    context.eval('var x = function(){return 22;}')
    assert_equal 22, context.eval('x()')
  end

  def test_can_attach_functions
    context = ExecJS.permissive_compile('')
    context.eval 'var adder'
    context.attach("adder", proc{|a,b| a+b})
    assert_equal 3, context.await('adder(1,2)')
  end

  def test_es6_arrow_functions
    context = ExecJS.compile('')
    assert_equal 42, context.eval('var adder=(x,y)=>x+y; adder(21,21);')
  end

  def test_concurrent_access
    context = ExecJS.compile('')
    context.eval('var counter=0; var plus=()=>counter++;')

    (1..10).map do
      Thread.new {
        context.eval("plus()")
      }
    end.each(&:join)

    assert_equal 10, context.eval("counter")
  end

  class FooError < StandardError
    def initialize(message)
      super(message)
    end
  end

  def test_attached_exceptions
    context = ExecJS.permissive_compile('')
    context.attach("adder", proc{ raise FooError, "I like foos" })
    assert_raises do
      begin
raise FooError, "I like foos"
        context.await('adder()')
      rescue => e
        assert_equal FooError, e.class
        assert_match( /I like foos/, e.message)
        # TODO backtrace splicing so js frames are injected
        raise
      end
    end
  end

  def test_attached_on_object
    context = ExecJS.permissive_compile('')
    context.eval 'var minion = {}'
    context.attach("minion.speak", proc{"banana"})
    assert_equal "banana", context.await("minion.speak()")
  end

  def test_attached_on_nested_object
    context = ExecJS.permissive_compile('')
    context.eval 'var minion = { kevin: {} }'
    context.attach("minion.kevin.speak", proc{"banana"})
    assert_equal "banana", context.await("minion.kevin.speak()")
  end

  def test_return_arrays
    context = ExecJS.permissive_compile('')
    context.eval 'var nose = {}'
    context.attach("nose.type", proc{["banana",["nose"]]})
    assert_equal ["banana", ["nose"]], context.await("nose.type()")
  end

  def test_return_hash
    context = ExecJS.permissive_compile('')
    context.attach("test", proc{{banana: :nose, "inner" => {'42' => 42}}})
    assert_equal({"banana" => "nose", "inner" => {"42" => 42}}, context.await("test()"))
  end

  def test_return_large_number
    context = ExecJS.permissive_compile('')
    test_num = 1_000_000_000_000_000
    context.attach("test", proc{test_num})

    assert_equal(true, context.await("test() === 1000000000000000"))
    assert_equal(test_num, context.await("test()"))
  end

  def test_return_int_max
    context = ExecJS.permissive_compile('')
    test_num = 2 ** (31) - 1 #last int32 number
    context.attach("test", proc{test_num})

    assert_equal(true, context.await("test() === 2147483647"))
    assert_equal(test_num, context.await("test()"))
  end

  module Echo
    def self.say(thing)
      thing
    end
  end

  def test_can_attach_simple_method
    context = ExecJS.permissive_compile('')
    context.attach("say", Echo.method(:say))
    assert_equal "hello", context.await("say('hello')")
  end

  def test_can_attach_method
    context = ExecJS.permissive_compile('')
    context.eval 'var Echo = {}'
    context.attach("Echo.say", Echo.method(:say))
    assert_equal "hello", context.await("Echo.say('hello')")
  end

  def test_attach_error
    context = ExecJS.compile('')
    context.eval("var minion = 2")
    assert_raises do
      begin
        context.attach("minion.kevin.speak", proc{"banana"})
      rescue => e
        assert_equal ExecJS::ParseError, e.class
        assert_match(/expecting minion.kevin/, e.message)
        raise
      end
    end
  end

  def test_context_from_file
    context = ExecJS.compile('', filename: File.dirname(__FILE__) + "/fixtures/file.js")
    assert_equal "world", context.eval("hello")
  end

  def test_contexts_can_be_safely_GCed
    context = ExecJS.compile('')
    context.eval 'var hello = "world";'

    context = nil
    GC.start
  end

  def test_error_on_return_val
    v8 = ExecJS.compile('')
    assert_raises(ExecJS::ProgramError) do
      v8.eval('var o = {}; o.__defineGetter__("bar", function() { return null(); }); o')
    end
  end

  def test_function_rval
    context = ExecJS.permissive_compile('')
    context.attach("echo", proc{|msg| msg})
    assert_equal("foo", context.await("echo('foo')"))
  end

  def test_promise
    context = ExecJS.compile('', )
    context.eval <<~JS
      var x = 0;
      async function test() {
        return 99;
      }

      test().then(v => x = v);
    JS

    v = context.eval("x");
    assert_equal(v, 99)
  end
end
