module Speednode
  class Runtime < ExecJS::Runtime
    class Context < ::ExecJS::Runtime::Context
      def initialize(runtime, source = "", options = {})
        @runtime = runtime
        @uuid = SecureRandom.uuid
        @runtime.register_context(@uuid, self)
        @permissive = !!options.delete(:permissive)
        @debug = @permissive ? !!options.delete(:debug) { false } : false
        @debug = false unless ENV['NODE_OPTIONS']&.include?('--inspect')
        @vm = @runtime.vm
        @timeout = options[:timeout] ? options[:timeout]/1000 : 600

        filename = options.delete(:filename)
        source = File.read(filename) if filename

        begin
          source = source.encode(Encoding::UTF_8)
        rescue
          source = source.force_encoding('UTF-8')
        end

        if @debug && @permissive
          raw_created(source, options)
        elsif @permissive
          raw_createp(source, options)
        else
          raw_create(source, options)
        end

        add_script(key: :_internal_exec_fin, source: '!global.__LastExecutionFinished')
      end

      # def options
      #   @vm.context_options(@uuid)
      # end

      def attach(func, procedure = nil, &block)
        raise "#attach requires a permissive context." unless @permissive
        run_block = block_given? ? block : procedure
        ::Speednode::Runtime.attach_proc(@uuid, func, run_block)
        @vm.attach(@uuid, func)
      end

      def await(source)
        raw_eval <<~JAVASCRIPT
          (async () => {
            global.__LastExecutionFinished = false;
            global.__LastResult = null;
            global.__LastErr = null;
            global.__LastResult = await #{source};
            global.__LastExecutionFinished = true;
          })().catch(function(err) {
            global.__LastResult = null;
            global.__LastErr = err;
            global.__LastExecutionFinished = true;
          })
        JAVASCRIPT
        await_result
      end

      def bench(source, _options = nil)
        raw_bench(source) if /\S/ =~ source
      end

      def call(identifier, *args)
        raw_eval("#{identifier}.apply(this, #{::Oj.dump(args, mode: :strict)})")
      end

      def eval(source, _options = nil)
        raw_eval(source) if /\S/ =~ source
      end

      def exec(source, _options = nil)
        raw_exec("(function(){#{source}})()")
      end

      def eval_script(key:)
        extract_result(@vm.evsc(@uuid, key))
      end

      def add_script(key:, source:)
        extract_result(@vm.scsc(@uuid, key, source.encode(Encoding::UTF_8)))
      end

      def permissive?
        @permissive
      end

      def permissive_eval(source, _options = nil)
        raise "Context not permissive!" unless @permissive
        raw_eval(source) if /\S/ =~ source
      end

      def permissive_exec(source, _options = nil)
        raise "Context not permissive!" unless @permissive
        raw_exec("(function(){#{source}})()")
      end

      def available?
        @runtime.context_registered?(@uuid)
      end

      def stop
        @runtime.unregister_context(@uuid)
      end

      protected

      def raw_bench(source)
        extract_result(@vm.bench(@uuid, source.encode(Encoding::UTF_8)))
      end

      def raw_eval(source)
        extract_result(@vm.eval(@uuid, source.encode(Encoding::UTF_8)))
      end

      def raw_exec(source)
        extract_result(@vm.exec(@uuid, source.encode(Encoding::UTF_8)))
      end

      def raw_create(source, options)
        source = source.encode(Encoding::UTF_8)
        result = @vm.create(@uuid, source, options)
        extract_result(result)
      end

      def raw_created(source, options)
        source = source.encode(Encoding::UTF_8)
        result = @vm.created(@uuid, source, options)
        extract_result(result)
      end

      def raw_createp(source, options)
        source = source.encode(Encoding::UTF_8)
        result = @vm.createp(@uuid, source, options)
        extract_result(result)
      end

      def extract_result(output)
        if output[0] == 'ok'
          output[1]
        else
          _status, value, stack = output
          stack ||= ""
          stack = stack.split("\n").map do |line|
            line.sub(" at ", "").strip
          end
          stack.reject! do |line|
            line.include?('(node:') ||
            line.include?('lib\speednode\runner.js') ||
            line.include?('lib/speednode/runner.js')
          end
          stack.shift unless stack[0].to_s.include?("(execjs)")
          error_class = value =~ /SyntaxError:/ ? ExecJS::RuntimeError : ExecJS::ProgramError
          error = error_class.new(value)
          error.set_backtrace(stack + caller)
          raise error
        end
      end

      def await_result
        start_time = ::Time.now
        while eval_script(key: :_internal_exec_fin) && !timed_out?(start_time)
          sleep 0.005
        end
        result = exec <<~JAVASCRIPT
          if (global.__LastExecutionFinished === true) {
            var err = global.__LastErr;
            var result = global.__LastResult;

            global.__LastErr = null;
            global.__LastResult = null;
            global.__LastExecutionFinished = false;

            if (err) { return ['err', ['', err].join(''), err.stack]; }
            else if (typeof result === 'undefined' && result !== null) { return ['ok']; }
            else {
                try { return ['ok', result]; }
                catch (err) { return ['err', ['', err].join(''), err.stack]; }
            }
          } else {
            var new_err = new Error('Last command did not yet finish execution!');
            return ['err', ['', new_err].join(''), new_err.stack];
          }
        JAVASCRIPT
        extract_result(result)
      end

      def timed_out?(start_time)
        if (::Time.now - start_time) > @timeout
          raise "Speednode: Command Execution timed out!"
        end
        false
      end
    end
  end
end
