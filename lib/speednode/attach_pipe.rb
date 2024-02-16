require 'ffi'

module Speednode
  module WindowsyThings
    extend FFI::Library

    ffi_lib :kernel32, :user32

    ERROR_IO_PENDING      = 997
    ERROR_PIPE_CONNECTED  = 535
    ERROR_SUCCESS         = 0

    FILE_FLAG_OVERLAPPED  = 0x40000000

    INFINITE              = 0xFFFFFFFF
    INVALID_HANDLE_VALUE  = FFI::Pointer.new(-1).address

    PIPE_ACCESS_DUPLEX    = 0x00000003
    PIPE_READMODE_BYTE    = 0x00000000
    PIPE_READMODE_MESSAGE = 0x00000002
    PIPE_TYPE_BYTE        = 0x00000000
    PIPE_TYPE_MESSAGE     = 0x00000004
    PIPE_WAIT             = 0x00000000

    QS_ALLINPUT           = 0x04FF

    typedef :uintptr_t, :handle

    attach_function :ConnectNamedPipe, [:handle, :pointer], :ulong
    attach_function :CreateEvent, :CreateEventA, [:pointer, :ulong, :ulong, :string], :handle
    attach_function :CreateNamedPipe, :CreateNamedPipeA, [:string, :ulong, :ulong, :ulong, :ulong, :ulong, :ulong, :pointer], :handle
    attach_function :DisconnectNamedPipe, [:handle], :bool
    attach_function :FlushFileBuffers, [:handle], :bool
    attach_function :GetLastError, [], :ulong
    attach_function :GetOverlappedResult, [:handle, :pointer, :pointer, :bool], :bool
    attach_function :MsgWaitForMultipleObjects, [:ulong, :pointer, :ulong, :ulong, :ulong], :ulong
    attach_function :ReadFile, [:handle, :buffer_out, :ulong, :pointer, :pointer], :bool
    attach_function :SetEvent, [:handle], :bool
    attach_function :WaitForMultipleObjects, [:ulong, :pointer, :ulong, :ulong], :ulong
    attach_function :WriteFile, [:handle, :buffer_in, :ulong, :pointer, :pointer], :bool
  end

  class AttachPipe
    include Speednode::WindowsyThings

    CONNECTING_STATE = 0
    READING_STATE    = 1
    WRITING_STATE    = 2
    INSTANCES        = 4
    PIPE_TIMEOUT     = 5000
    BUFFER_SIZE      = 65536

    class Overlapped < FFI::Struct
      layout(
        :Internal, :uintptr_t,
        :InternalHigh, :uintptr_t,
        :Offset, :ulong,
        :OffsetHigh, :ulong,
        :hEvent, :uintptr_t
      )
    end

    def initialize(pipe_name, block)
      @run_block = block
      @full_pipe_name = "\\\\.\\pipe\\#{pipe_name}"
      @instances = 1
      @events = []
      @events_pointer = FFI::MemoryPointer.new(:uintptr_t, @instances + 1)
      @pipe = {}
    end

    def run
      @running = true
      create_instance
      while_loop
    end

    def stop
      @running = false
      warn("DisconnectNamedPipe failed with #{GetLastError()}") if !DisconnectNamedPipe(@pipe[:instance])
    end

    private

    def create_instance
      @events[0] = CreateEvent(nil, 1, 1, nil)
      raise "CreateEvent failed with #{GetLastError()}" unless @events[0]

      overlap = Overlapped.new
      overlap[:hEvent] = @events[0]

      @pipe = { overlap: overlap, instance: nil, request: FFI::Buffer.new(1, BUFFER_SIZE), bytes_read: 0, reply: FFI::Buffer.new(1, BUFFER_SIZE), bytes_to_write: 0, state: nil, pending_io: false }
      @pipe[:instance] = CreateNamedPipe(@full_pipe_name,
                                        PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
                                        PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT,
                                        4,
                                        BUFFER_SIZE,
                                        BUFFER_SIZE,
                                        PIPE_TIMEOUT,
                                        nil)
      raise "CreateNamedPipe failed with #{GetLastError()}" if @pipe[:instance] == INVALID_HANDLE_VALUE
      @pipe[:pending_io] = connect_to_new_client
      @pipe[:state] = @pipe[:pending_io] ? CONNECTING_STATE : READING_STATE

      @events_pointer.write_array_of_ulong_long(@events)
      nil
    end

    def while_loop
      while @running
        # this sleep gives other ruby threads a chance to run
        # ~10ms is a ruby thread time slice, so we choose something a bit larger
        # that ruby or the os is free to switch threads
        sleep 0.010 if @pipe[:state] != WRITING_STATE && @pipe[:state] != READING_STATE

        i = MsgWaitForMultipleObjects(@instances, @events_pointer, 0, 1, QS_ALLINPUT) if @pipe[:state] != WRITING_STATE

        if i > 0
          next
        end

        if @pipe[:pending_io]
          bytes_transferred = FFI::MemoryPointer.new(:ulong)
          success = GetOverlappedResult(@pipe[:instance], @pipe[:overlap], bytes_transferred, false)

          case @pipe[:state]
          when CONNECTING_STATE
            raise "Error #{GetLastError()}" unless success
            @pipe[:state] = READING_STATE
          when READING_STATE
            if !success || bytes_transferred.read_ulong == 0
              disconnect_and_reconnect(i)
              next
            else
              @pipe[:bytes_read] = bytes_transferred.read_ulong
              @pipe[:state] = WRITING_STATE
            end
          when WRITING_STATE
            if !success || bytes_transferred.read_ulong != @pipe[:bytes_to_write]
              disconnect_and_reconnect(i)
              next
            else
              @pipe[:state] = READING_STATE
            end
          else
            raise "Invalid pipe state."
          end
        end

        case @pipe[:state]
        when READING_STATE
          bytes_read = FFI::MemoryPointer.new(:ulong)
          success = ReadFile(@pipe[:instance], @pipe[:request], BUFFER_SIZE, bytes_read, @pipe[:overlap].to_ptr)
          if success && bytes_read.read_ulong != 0
            @pipe[:pending_io] = false
            @pipe[:state] = WRITING_STATE
            next
          end

          err = GetLastError()
          if !success && err == ERROR_IO_PENDING
            @pipe[:pending_io] = true
            next
          end

          disconnect_and_reconnect
        when WRITING_STATE
          @pipe[:reply] = @run_block.call(@pipe[:request].get_string(0))
          @pipe[:bytes_to_write] = @pipe[:reply].bytesize
          bytes_written = FFI::MemoryPointer.new(:ulong)
          success = WriteFile(@pipe[:instance], @pipe[:reply], @pipe[:bytes_to_write], bytes_written, @pipe[:overlap].to_ptr)

          if success && bytes_written.read_ulong == @pipe[:bytes_to_write]
            @pipe[:pending_io] = false
            @pipe[:state] = READING_STATE
            next
          end

          err = GetLastError()

          if !success && err == ERROR_IO_PENDING
            @pipe[:pending_io] = true
            next
          end

          disconnect_and_reconnect
        else
          raise "Invalid pipe state."
        end
      end
    end

    def disconnect_and_reconnect
      FlushFileBuffers(@pipe[:instance])
      warn("DisconnectNamedPipe failed with #{GetLastError()}") if !DisconnectNamedPipe(@pipe[:instance])

      @pipe[:pending_io] = connect_to_new_client

      @pipe[:state] = @pipe[:pending_io] ? CONNECTING_STATE : READING_STATE
    end

    def connect_to_new_client
      pending_io = false
      @pipe[:request].clear
      @pipe[:reply].clear
      connected = ConnectNamedPipe(@pipe[:instance], @pipe[:overlap].to_ptr)
      last_error = GetLastError()
      raise "ConnectNamedPipe failed with #{last_error} - #{connected}" if connected != 0

      case last_error
      when ERROR_IO_PENDING
        pending_io = true
      when ERROR_PIPE_CONNECTED
        SetEvent(@pipe[:overlap][:hEvent])
      when ERROR_SUCCESS
        pending_io = true
      else
        raise "ConnectNamedPipe failed with error #{last_error}"
      end

      pending_io
    end
  end
end
