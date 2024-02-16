require 'test_helper'

class TestSpeednode < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Speednode::VERSION
  end

  def test_precompiling_and_running_scripts
    context = ExecJS.compile('')
    context.add_script(key: 'test', source: '2 + 2')
    assert_equal 4, context.eval_script(key: 'test')
  end

  def test_precompiling_and_running_multiple_scripts
    context = ExecJS.compile('')
    context.add_script(key: :test1, source: '2 + 2')
    context.add_script(key: :test2, source: '4 + 4')
    assert_equal 4, context.eval_script(key: :test1)
    assert_equal 8, context.eval_script(key: :test2)
  end

  def test_benchmarking
    result = ExecJS.permissive_bench('2 + 2')
    assert_equal 4, result['result']
    assert_equal true, result['duration'] > 0
  end

  def test_stop_context
    contexts = ExecJS::Runtimes::Speednode.instance_variable_get(:@contexts)
    count = contexts.size
    context = ExecJS.compile('')
    assert_equal count + 1, contexts.size
    ExecJS::Runtimes::Speednode.stop_context(context)
    assert_equal count, contexts.size
  end
end
