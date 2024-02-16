require 'bundler/setup'
Bundler.require
if RUBY_PLATFORM =~ /linux/
  require 'mini_racer'
end
require 'benchmark'

TIMES = 1000
CALL_TIMES = 1000
SOURCE = File.read(File.expand_path("./fixtures/coffee-script.js", File.dirname(__FILE__))).freeze
EXCLUDED_RUNTIMES = [ExecJS::Runtimes::Bun, ExecJS::Runtimes::JavaScriptCore, ExecJS::Runtimes::V8, ExecJS::Runtimes::JScript, ExecJS::Runtimes::Node]

Benchmark.bmbm do |x|
  ExecJS::Runtimes.runtimes.reject {|r| EXCLUDED_RUNTIMES.include?(r)}.each do |runtime|
    next if !runtime.available? || runtime.deprecated?
    x.report("#{runtime.name}: CoffeeScript call") do
      ExecJS.runtime = runtime
      context = ExecJS.compile(SOURCE)

      TIMES.times do
        context.call("CoffeeScript.eval", "((x) -> x * x)(8)")
      end
    end

    ExecJS.runtime = runtime
    context = ExecJS.compile(SOURCE)

    x.report("#{runtime.name}: CoffeeScript call ctx") do
      TIMES.times do
        context.call("CoffeeScript.eval", "((x) -> x * x)(8)")
      end
    end
  end
end

puts "\n"
Benchmark.bmbm do |x|
  ExecJS::Runtimes.runtimes.reject {|r| EXCLUDED_RUNTIMES.include?(r)}.each do |runtime|
    next if !runtime.available? || runtime.deprecated?

    x.report("#{runtime.name}: CoffeeScript eval") do
      ExecJS.runtime = runtime
      context = ExecJS.compile(SOURCE)

      TIMES.times do
        context.eval("CoffeeScript.eval('((x) -> x * x)(8)')")
      end
    end

    ExecJS.runtime = runtime
    context = ExecJS.compile(SOURCE)

    x.report("#{runtime.name}: CoffeeScript eval ctx") do
      TIMES.times do
        context.eval("CoffeeScript.eval('((x) -> x * x)(8)')")
      end
    end

    if runtime == ExecJS::Runtimes::Speednode
      ExecJS.runtime = runtime
      context = ExecJS.compile(SOURCE)
      context.add_script(key: :coffee, source: "CoffeeScript.eval('((x) -> x * x)(8)')")

      x.report("#{runtime.name}: CoffeeScript eval scsc") do
        TIMES.times do
          context.eval_script(key: :coffee)
        end
      end
    end
  end
end

puts "\n"
Benchmark.bmbm do |x|
  ExecJS::Runtimes.runtimes.reject {|r| EXCLUDED_RUNTIMES.include?(r)}.each do |runtime|
    next if !runtime.available? || runtime.deprecated?

    x.report("#{runtime.name}: Eval overhead") do
      ExecJS.runtime = runtime
      context = ExecJS.compile('')

      CALL_TIMES.times do
        context.eval("true")
      end
    end

    ExecJS.runtime = runtime
    context = ExecJS.compile('')

    x.report("#{runtime.name}: Eval overhead ctx") do
      CALL_TIMES.times do
        context.eval("true")
      end
    end

    if runtime == ExecJS::Runtimes::Speednode
      ExecJS.runtime = runtime
      context = ExecJS.compile('')
      context.add_script(key: :ev, source: "true")

      x.report("#{runtime.name}: Eval overhead scsc") do
        CALL_TIMES.times do
          context.eval_script(key: :ev)
        end
      end
    end
  end
end

puts "\n"
Benchmark.bmbm do |x|
  ExecJS::Runtimes.runtimes.reject {|r| EXCLUDED_RUNTIMES.include?(r)}.each do |runtime|
    next if !runtime.available? || runtime.deprecated?

    x.report("#{runtime.name}: Call overhead") do
      ExecJS.runtime = runtime
      context = ExecJS.compile('')

      CALL_TIMES.times do
        context.call("(function(arg) {return arg;})","true")
      end
    end

    ExecJS.runtime = runtime
    context = ExecJS.compile('')

    x.report("#{runtime.name}: Call overhead ctx") do
      CALL_TIMES.times do
        context.call("(function(arg) {return arg;})","true")
      end
    end
  end
end


puts "\nPermissive: call benchmark:"
Benchmark.bmbm do |x|
  x.report(ExecJS::Runtimes::Speednode.name + ' coffee') do
    ExecJS.runtime = ExecJS::Runtimes::Speednode
    context = ExecJS.permissive_compile(SOURCE)

    TIMES.times do
      context.call("CoffeeScript.eval", "((x) -> x * x)(8)")
    end
  end

  ExecJS.runtime = ExecJS::Runtimes::Speednode
  context = ExecJS.permissive_compile(SOURCE)
  x.report(ExecJS::Runtimes::Speednode.name + ' coffee ctx') do
    TIMES.times do
      context.call("CoffeeScript.eval", "((x) -> x * x)(8)")
    end
  end
end

puts "\nPermissive: eval benchmark:"
Benchmark.bmbm do |x|
  x.report(ExecJS::Runtimes::Speednode.name + ' coffee') do
    ExecJS.runtime = ExecJS::Runtimes::Speednode
    context = ExecJS.permissive_compile(SOURCE)

    TIMES.times do
      context.eval("CoffeeScript.eval('((x) -> x * x)(8)')")
    end
  end

  ExecJS.runtime = ExecJS::Runtimes::Speednode
  context = ExecJS.permissive_compile(SOURCE)

  x.report(ExecJS::Runtimes::Speednode.name + ' coffee ctx') do
    TIMES.times do
      context.eval("CoffeeScript.eval('((x) -> x * x)(8)')")
    end
  end
end

puts "\nPermissive: eval overhead benchmark:"
Benchmark.bmbm do |x|
  x.report(ExecJS::Runtimes::Speednode.name) do
    ExecJS.runtime = ExecJS::Runtimes::Speednode
    context = ExecJS.permissive_compile('')

    CALL_TIMES.times do
      context.eval("true")
    end
  end

  ExecJS.runtime = ExecJS::Runtimes::Speednode
  context = ExecJS.permissive_compile('')

  x.report(ExecJS::Runtimes::Speednode.name) do
    CALL_TIMES.times do
      context.eval("true")
    end
  end
end

puts "\nPermissive: call overhead benchmark:"
Benchmark.bmbm do |x|
  x.report(ExecJS::Runtimes::Speednode.name) do
    ExecJS.runtime = ExecJS::Runtimes::Speednode
    context = ExecJS.permissive_compile('')

    CALL_TIMES.times do
      context.call("(function(arg) {return arg;})","true")
    end
  end

  ExecJS.runtime = ExecJS::Runtimes::Speednode
  context = ExecJS.permissive_compile('')

  x.report(ExecJS::Runtimes::Speednode.name + ' ctx') do
    CALL_TIMES.times do
      context.call("(function(arg) {return arg;})","true")
    end
  end
end

puts "\nRuby method call overhead benchmark\\attach/context:"
Benchmark.bmbm do |x|
  ExecJS.runtime = ExecJS::Runtimes::Speednode
  s_context = ExecJS.permissive_compile('')
  s_context.attach('foo', proc { true })
  s_context.await('foo("bar")')

  s_context.eval <<~JAVASCRIPT
    async function bench() {
      let val;
      for (let i = 0; i < #{CALL_TIMES}; i++) {
        val = await foo(i);
      }
      return val;
    }
  JAVASCRIPT

  x.report(ExecJS::Runtimes::Speednode.name) do
    1.times do
      s_context.await("bench()")
    end
  end

  unless Gem.win_platform?
    m_context = MiniRacer::Context.new
    m_context.attach('foo', proc { true })
    m_context.eval('foo("bar")')

    m_context.eval <<~JAVASCRIPT
      function bench() {
        let val;
        for (let i = 0; i < #{CALL_TIMES}; i++) {
          val = foo(i);
        }
        return val;
      }
    JAVASCRIPT

    x.report(ExecJS::Runtimes::MiniRacer.name) do
      1.times do
        m_context.eval("bench()")
      end
    end
  end
end


puts "\nPermissive: await call overhead benchmark\\attach/context:"
Benchmark.bmbm do |x|
  ExecJS.runtime = ExecJS::Runtimes::Speednode
  context = ExecJS.permissive_compile('')
  context.eval <<~JAVASCRIPT
    async function foo(val) {
      return new Promise(function (resolve, reject) { resolve(val); });
    }
  JAVASCRIPT

  x.report(ExecJS::Runtimes::Speednode.name) do
    CALL_TIMES.times do |i|
      context.await("foo(#{i})")
    end
  end
end
