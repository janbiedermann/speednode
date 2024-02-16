require 'test_helper'
require 'timeout'
require "minitest/autorun"
require "execjs/module"

begin
  require "execjs"
rescue ExecJS::RuntimeUnavailable => e
  warn e
  exit 2
end

class SpeednodeFunctionTest < Minitest::Test
  def test_fun
    context = ExecJS.compile('')
    context.eval("function f(x) { return 'I need ' + x + ' foos' }")
    assert_equal context.eval('f(10)'), 'I need 10 foos'

    assert_raises(ArgumentError) do
      context.call
    end

    count = 4
    res = context.call('f', count)
    assert_equal "I need #{count} foos", res
  end

  def test_non_existing_function
    context = ExecJS.compile('')
    context.eval("function f(x) { return 'I need ' + x + ' galettes' }")

    # f is defined, let's call g
    # mini_racer expects RuntimeError, but that conflicts with ExecJS, ProgramError seems correct
    assert_raises(ExecJS::ProgramError) do
      context.call('g')
    end
  end

  def test_throwing_function
    context = ExecJS.compile('')
    context.eval('function f(x) { throw new Error("foo bar") }')

    # mini_racer expects RuntimeError, but that conflicts with ExecJS, ProgramError seems correct
    err = assert_raises(ExecJS::ProgramError) do
      context.call('f', 1)
    end
    assert_equal err.message, 'Error: foo bar'
    i = err.backtrace.index('f ((execjs):1:23)')
    i = 0 unless i
    assert_match(/\(execjs\):1:23/, err.backtrace[i])
  end

  def test_args_types
    context = ExecJS.compile('')
    context.eval("function f(x, y) { return 'I need ' + x + ' ' + y }")

    res = context.call('f', 3, 'bars')
    assert_equal 'I need 3 bars', res

    res = context.call('f', { a: 1 }, 'bars')
    assert_equal 'I need [object Object] bars', res

    res = context.call('f', [1, 2, 3], 'bars')
    assert_equal 'I need 1,2,3 bars', res
  end

  def test_complex_return
    context = ExecJS.compile('')
    context.eval('function f(x, y) { return { vx: x, vy: y, array: [x, y] } }')

    h = { 'vx' => 3, 'vy' => 'bars', 'array' => [3, 'bars'] }
    res = context.call('f', 3, 'bars')
    assert_equal h, res
  end

  def test_map_return
    context = ExecJS.compile('')
    context.eval('function f(x, y) { return { vx: x, vy: y, array: [x, y], map: new Map([[y, x]]) } }')

    h = { 'vx' => 3, 'vy' => 'bars', 'array' => [3, 'bars'], 'map' => { 'bars' => 3 } }
    res = context.call('f', 3, 'bars')
    assert_equal h, res
  end

  def test_do_not_hang_with_concurrent_calls
    context = ExecJS.compile('')
    context.eval("function f(x) { return 'I need ' + x + ' foos' }")

    thread_count = 2

    threads = []
    thread_count.times do
      threads << Thread.new do
        10.times do |i|
          context.call('f', i)
        end
      end
    end

    joined_thread_count = 0
    for t in threads do
      joined_thread_count += 1
      t.join
    end

    # Dummy test, completing should be enough to show we don't hang
    assert_equal thread_count, joined_thread_count
  end
end
