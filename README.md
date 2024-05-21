# Speednode

A fast runtime for ExecJS using node js. Works on Linux, BSDs, MacOS and Windows.
Inspired by [execjs-fastnode](https://github.com/jhawthorn/execjs-fastnode).

### Installation

In Gemfile:
`gem 'speednode'`, then `bundle install`

### Configuration

Speednode provides one node based runtime `Speednode` which runs scripts in node vms.
The runtime can be chosen by:

```ruby
ExecJS.runtime = ExecJS::Runtimes::Speednode
```
If node cant find node modules for the permissive contexts (see below), its possible to set the load path before assigning the runtime:
```ruby
ENV['NODE_PATH'] = './node_modules'
```

### Contexts

Each ExecJS context runs in a node vm. Speednode offers two kinds of contexts:
- a compatible context, which is compatible with default ExecJS behavior.
- a permissive context, which is more permissive and allows to `require` node modules.

#### Compatible
A compatible context can be created with the standard `ExecJS.compile` or code can be executed within a compatible context by using the standard `ExecJS.eval` or `ExecJS.exec`.
Example for a compatible context:
```ruby
compat_context = ExecJS.compile('Test = "test"')
compat_context.eval('1+1')
```
#### Permissive
A permissive context can be created with `ExecJS.permissive_compile` or code can be executed within a permissive context by using
`ExecJS.permissive_eval` or `ExecJS.permissive_exec`.
Example for a permissive context:
```ruby
perm_context = ExecJS.permissive_compile('Test = "test"')
perm_context.eval('1+1')
```
Evaluation in a permissive context:
```ruby
ExecJS.permissive_eval('1+1')
```

#### Stopping Contexts
Contexts should be stopped programmatically when no longer needed.
```ruby
context = ExecJS.compile('Test = "test"') # will start a node process
ExecJS::Runtimes::Speednode.stop_context(context) # will kill the node process
```

### Precompiling and Storing scripts for repeated execution

Scripts can be precompiled and stored for repeated execution, which leads to a significant performance improvement, especially for larger scripts:
```ruby
context = ExecJS.compile('Test = "test"')
context.add_script(key: 'super', source: some_large_javascript) # will compile and store the script
context.eval_script(key: 'super') # will run the precompiled script in the context
```
For the actual performance benefit see below.

### Async function support

Its possible to call async functions synchronously from ruby using Context#await:
```ruby
context = ExecJS.compile('')
context.eval <<~JAVASCRIPT
  async function foo(val) {
    return new Promise(function (resolve, reject) { resolve(val); });
  }
JAVASCRIPT

context.await("foo('test')") # => 'test'
```

### Attaching ruby methods to Permissive Contexts

Ruby methods can be attached to Permissive Contexts using Context#attach:
```ruby
  context = ExecJS.permissive_compile(SOURCE)
  context.attach('foo') { |v| v }
  context.await('foo("bar")')
```
The attached method is reflected in the context by a async javascript function. From within javascript the ruby method is best called using await:
```javascript
r = await foo('test');
```
or via context#await as in above example.
Attaching and calling ruby methods to/from permissive contexts is not that fast. It is recommended to use it sparingly.

### Benchmarks

Highly scientific, maybe.

1000 rounds using speednode 0.8.0 with node 20.11.0 on a older CPU on Linux
(ctx = using context, scsc = using precompiled scripts):
```
ExecJS CoffeeScript eval:            real
Speednode Node.js (V8):          0.324355
Speednode Node.js (V8) ctx:      0.276933
Speednode Node.js (V8) scsc:     0.239678
mini_racer (0.8.0):              0.204274
mini_racer (0.8.0) ctx:          0.134327

Eval overhead benchmark:             real
Speednode Node.js (V8):          0.064198
Speednode Node.js (V8) ctx:      0.065521
Speednode Node.js (V8) scsc:     0.050652
mini_racer (0.8.0):              0.010653
mini_racer (0.8.0) ctx:          0.007764
```

To run benchmarks:
- clone repo
- `bundle install`
- `bundle exec rake bench`

### Tests

To run tests:
- clone repo
- `bundle install`
- `bundle exec rake`
