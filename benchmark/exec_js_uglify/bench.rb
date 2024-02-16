require 'fileutils'
require 'benchmark'

if RUBY_PLATFORM =~ /linux/
  engines = {
    'speednode': proc { ExecJS::Runtimes::Speednode },
    mini_racer: proc { ExecJS::MiniRacerRuntime.new },
    node: proc { ExecJS::Runtimes::Node }
  }
else
  engines = {
    'speednode': proc { ExecJS::Runtimes::Speednode }
  }
end

Dir.chdir(File.dirname(__FILE__))
unless defined? Bundler
  system "bundle"
  exec "bundle exec ruby bench.rb"
end

engines.each do |engine, _b|
  unless engine == :node
    require engine.to_s
  end
end

require 'uglifier'

puts "\nminify discourse_app.js:"
Benchmark.bmbm do |x|
  engines.each do |engine, b|
    ExecJS.runtime = b.call

    x.report(engine) do
      1.times do
        Uglifier.compile(File.read("helper_files/discourse_app.js"))
      end
    end
  end
end

puts "\nminify discourse_app_minified.js:"
Benchmark.bmbm do |x|
  engines.each do |engine, b|
    ExecJS.runtime = b.call

    x.report(engine) do
      1.times do
        Uglifier.compile(File.read("helper_files/discourse_app_minified.js"))
      end
    end
  end
end

puts "\nminify discourse_app.js twice (2 threads):"
Benchmark.bmbm do |x|
  engines.each do |engine, b|
    ExecJS.runtime = b.call

    x.report(engine) do
      1.times do
        (0..1).map do
          Thread.new do
            Uglifier.compile(File.read("helper_files/discourse_app.js"))
          end
        end.each(&:join)
      end
    end
  end
end
