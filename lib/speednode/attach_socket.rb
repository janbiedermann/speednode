require 'socket'

module Speednode
  class AttachSocket

    attr_reader :socket

    def initialize(socket_path, block)
      @socket_path = socket_path
      @run_block = block
    end

    def run
      @running = true
      client = nil
      ret = nil
      @socket = UNIXServer.new(@socket_path)

      while @running do
        if ret
          begin
            client = @socket.accept_nonblock
            request = client.gets("\x04")
            result = @run_block.call(request)
            client.write result
            client.flush
            client.close
          rescue Errno::EAGAIN, Errno::EWOULDBLOCK
          end
        end
        ret = begin
                IO.select([@socket], nil, nil, nil) || next
              rescue Errno::EBADF
              end
      end
    end

    def stop
      @running = false
      @socket.close
    end
  end
end
