require 'bundler/gem_tasks'
require 'rake/testtask'
require_relative 'lib/speednode/version'

task :bench_execjs do
  sh 'ruby -Ilib -r./test/shim test/bench.rb'
end

task :bench_uglify do
  sh 'ruby benchmark/exec_js_uglify/bench.rb'
end

task bench: %i[bench_execjs bench_uglify]

task :update_bundle do
  system('bundle update')
end

task test: :update_bundle do
  puts <<~'ASCII'
                           __             __
      ___ ___  ___ ___ ___/ /__  ___  ___/ /__
     (_-</ _ \/ -_) -_) _  / _ \/ _ \/ _  / -_)
    /___/ .__/\__/\__/\_,_/_//_/\___/\_,_/\__/
       /_/
  ASCII
  ENV['EXECJS_RUNTIME'] = 'Speednode'
end

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList[
    'test/shim.rb',
    'test/test_execjs.rb',
    'test/test_speednode.rb',
    'test/test_permissive_execjs.rb',
    # following taken and adapted from mini_racer
    'test/test_racer_function.rb',
    'test/test_racer_speednode.rb'
  ]
end

task default: :test
