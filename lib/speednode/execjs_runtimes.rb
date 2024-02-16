module ExecJS
  module Runtimes
    Speednode = Speednode::Runtime.new(
      name: 'Speednode Node.js (V8)',
      command: %w[node nodejs],
      runner_path: File.join(File.dirname(__FILE__), 'runner.js'),
      encoding: 'UTF-8'
    )
    runtimes.unshift(Speednode)
  end
end
