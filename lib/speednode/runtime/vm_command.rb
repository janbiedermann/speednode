module Speednode
  class Runtime < ExecJS::Runtime
    class VMCommand
      def initialize(socket, cmd, arguments)
        @socket = socket
        @cmd = cmd
        @arguments = arguments
      end

      def execute
        result = ''
        message = ::Oj.dump({ 'cmd' => @cmd, 'args' => @arguments }, mode: :strict)
        message = message + "\x04"
        bytes_to_send = message.bytesize
        sent_bytes = 0

        if ::ExecJS.windows?
          @socket.write(message)
          begin
            result << @socket.read
          end until result.end_with?("\x04")
        else
          sent_bytes = @socket.sendmsg(message)
          if sent_bytes < bytes_to_send
            while sent_bytes < bytes_to_send
              sent_bytes += @socket.sendmsg(message.byteslice((sent_bytes)..-1))
            end
          end

          begin
            result << @socket.recvmsg()[0]
          end until result.end_with?("\x04")
        end
        ::Oj.load(result.chop!, mode: :strict)
      end
    end
  end
end
