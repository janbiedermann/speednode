if Gem.win_platform?
  require 'securerandom'
  require 'win32/pipe'

  module Win32
    class Pipe
      def write(data)
        bytes = ::FFI::MemoryPointer.new(:ulong)

        raise Error, "no pipe created" unless @pipe

        if @asynchronous
          bool = WriteFile(@pipe, data, data.bytesize, bytes, @overlapped)
          bytes_written = bytes.read_ulong

          if bool && bytes_written > 0
            @pending_io = false
            return true
          end

          error = GetLastError()
          if !bool && error == ERROR_IO_PENDING
            @pending_io = true
            return true
          end

          return false
        else
          unless WriteFile(@pipe, data, data.bytesize, bytes, nil)
            raise SystemCallError.new("WriteFile", FFI.errno)
          end

          return true
        end
      end
    end
  end
end

module Speednode
  class Runtime < ExecJS::Runtime
    class VM
      def self.finalize(socket, socket_dir, socket_path, pid)
        proc do
          ::Speednode::Runtime.responders[socket_path].kill if ::Speednode::Runtime.responders[socket_path]
          exit_node(socket, socket_dir, socket_path, pid)
        end
      end

      def self.exit_node(socket, socket_dir, socket_path, pid)
        VMCommand.new(socket, "exit", 0).execute rescue nil
        socket.close
        File.unlink(socket_path) if File.exist?(socket_path)
        Dir.rmdir(socket_dir) if socket_dir && Dir.exist?(socket_dir)
        if Gem.win_platform?
          # SIGINT or SIGKILL are unreliable on Windows, try native taskkill first
          unless system("taskkill /f /t /pid #{pid} >NUL 2>NUL")
            Process.kill('KILL', pid) rescue nil
          end
        else
          Process.kill('KILL', pid) rescue nil
        end
      rescue
        nil
      end

      attr_reader :responder

      def initialize(options)
        @mutex = ::Thread::Mutex.new
        @socket_path = nil
        @options = options
        @started = false
        @socket = nil
      end

      def started?
        @started
      end

      def evsc(context, key)
        command('evsc', { 'context' => context, 'key' => key })
      end

      def scsc(context, key, source)
        command('scsc', { 'context' => context, 'key' => key, 'source' => source })
      end

      def eval(context, source)
        command('eval', {'context' => context, 'source' => source})
      end

      def exec(context, source)
        command('exec', {'context' => context, 'source' => source})
      end

      def bench(context, source)
        command('bench', {'context' => context, 'source' => source})
      end

      def create(context, source, options)
        command('create', {'context' => context, 'source' => source, 'options' => options})
      end

      def created(context, source, options)
        command('created', {'context' => context, 'source' => source, 'options' => options})
      end

      def createp(context, source, options)
        command('createp', {'context' => context, 'source' => source, 'options' => options})
      end

      def attach(context, func)
        create_responder(context) unless responder
        command('attach', {'context' => context, 'func' => func })
      end

      def delete_context(context)
        @mutex.synchronize do
          VMCommand.new(@socket, "deleteContext", context).execute rescue nil
        end
      rescue ThreadError
        nil
      end

      # def context_options(context)
      #   command('ctxo', {'context' => context })
      # end

      def start
        @mutex.synchronize do
          start_without_synchronization
        end
      end

      def stop
        return unless @started
        @mutex.synchronize do
          self.class.exit_node(@socket, @socket_dir, @socket_path, @pid)
          @socket_path = nil
          @started = false
          @socket = nil
        end
      end

      private

      def start_without_synchronization
        return if @started
        if ExecJS.windows?
          @socket_dir = nil
          @socket_path = SecureRandom.uuid
        else
          @socket_dir = Dir.mktmpdir("speednode-")
          @socket_path = File.join(@socket_dir, "socket")
        end
        @pid = Process.spawn({"SOCKET_PATH" => @socket_path}, @options[:binary], '--expose-gc', @options[:source_maps], @options[:runner_path])
        Process.detach(@pid)

        retries = 500

        if ExecJS.windows?
          timeout_or_connected = false
          begin
            retries -= 1
            begin
              @socket = Win32::Pipe::Client.new(@socket_path, Win32::Pipe::ACCESS_DUPLEX)
            rescue
              sleep 0.1
              raise "Unable to start nodejs process in time" if retries == 0
              next
            end
            timeout_or_connected = true
          end until timeout_or_connected
        else
          while !File.exist?(@socket_path)
            sleep 0.1
            retries -= 1
            raise "Unable to start nodejs process in time" if retries == 0
          end

          @socket = UNIXSocket.new(@socket_path)
        end

        @started = true

        exit_proc = self.class.finalize(@socket, @socket_dir, @socket_path, @pid)

        Kernel.at_exit { exit_proc.call }
      end

      def create_responder(context)
        start unless @started
        run_block = Proc.new do |request|
          args = ::Oj.load(request.chop!, mode: :strict)
          req_context = args[0]
          method = args[1]
          method_args = args[2]
          begin
            result = ::Speednode::Runtime.attached_procs[req_context][method].call(*method_args)
            ::Oj.dump(['ok', result], mode: :strict)
          rescue Exception => err
            ::Oj.dump(['err', err.class.to_s, [err.message].concat(err.backtrace)], mode: :strict)
          end
        end
        responder_path = @socket_path + '_responder'
        @responder = Thread.new do
                                  if ExecJS.windows?
                                    ::Speednode::AttachPipe.new(responder_path, run_block).run
                                  else
                                    ::Speednode::AttachSocket.new(responder_path, run_block).run
                                  end
                                end
        ::Speednode::Runtime.responders[@socket_path] = @responder_thread
        @responder.run
      end

      def command(cmd, argument)
        @mutex.synchronize do
          start_without_synchronization unless @started
          VMCommand.new(@socket, cmd, argument).execute
        end
      end
    end
  end
end
