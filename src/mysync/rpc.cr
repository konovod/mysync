require "cannon"
require "cannon/rpc"
require "./commands"

module MySync
  private alias ReceiveChannel = Channel(IO::Memory)

  # mostly copied from cannon/tcp_connection. optimize later?
  class CannonInterface < Cannon::Rpc::Connection
    getter manager

    def initialize(@endpoint : EndPoint, amanager : Cannon::Rpc::Manager)
      super(amanager)
      @handles = Hash(UInt8, ReceiveChannel).new
    end

    private def send_buffer
      io = IO::Memory.new
      yield io
      @endpoint.cmd_buffer.add io.to_slice
    end

    private def find_handle
      id = (0u8..255u8).find { |i| !@handles.includes?(i) }

      if id.nil?
        raise "Unable to find unused handle!"
      end

      id
    end

    private def send_call(service_id, function_hash, arguments, handle, wait)
      header = Cannon::Rpc::Protocol::Header.new(
        flags: wait ? Cannon::Rpc::Protocol::Flags::None : Cannon::Rpc::Protocol::Flags::VoidCall,
        handle: handle,
        service_id: service_id,
        method: function_hash,
      )
      send_buffer do |io|
        Cannon.encode(io, header)
        Cannon.encode(io, arguments)
      end
    end

    # Calls the function (through *function_hash*) on *service_id* using
    # *arguments*.  Yields an `IO` when the response was received and must
    # be read from it using `Cannon.decode`.  If a remote error was
    # encountered, the block is *not* called, and is raised locally.
    #
    # This method blocks the current Fiber.
    def call_remotely(service_id : UInt32, function_hash : UInt32, arguments : Tuple?, &block : IO -> _)
      handle = find_handle

      ch = ReceiveChannel.new
      @handles[handle] = ch

      send_call service_id, function_hash, arguments, handle, true

      io = ch.receive
      @handles.delete handle
      yield(io)
    end

    # Like `call_remotely`, but doesn't request a response.  A response is
    # never requested and thus is never received.
    #
    # **Note**: This will also silence any error propagation from the remote
    # side back to the local side.
    #
    # This method **does not** block the current Fiber.
    def call_remotely(service_id : UInt32, function_hash : UInt32, arguments : Tuple?) : Nil
      send_call service_id, function_hash, arguments, 0u8, false
    end

    # Releases the remote *service_id*
    def release_remote_service(service_id : UInt32) : Nil
      send_call(0xFFFFFFFFu32, 0xFFFFFFFFu32, service_id, 0u8, false)
    end

    # Starts a read-loop, blocking the current Fiber.
    def run
      # do nothing
    end

    # called from listener fiber
    def handle_command(io : IO)
      header = Cannon.decode(io, Cannon::Rpc::Protocol::Header)

      if header.flags.result_value?
        handle_response header, io
      elsif header.service_id == 0xFFFFFFFFu32 && header.method == 0xFFFFFFFFu32
        handle_release io
      else
        handle_call header, io
      end
    end

    private def handle_release(io)
      service_id = Cannon.decode io, UInt32
      @manager.release service_id, owner: self
    end

    private def handle_response(header, io)
      if waiter = @handles[header.handle]?
        waiter.send io
      else
        raise "Unknown response with handle #{header.handle}"
      end
    end

    private def handle_call(header, io)
      target_service = @manager[header.service_id]
      # TODO - async calling as in cannon?
      results = target_service.rpc_invoke(header.method, io, self)
      return if header.flags.void_call?
      header.flags = Cannon::Rpc::Protocol::Flags.flags(ResultValue)
      send_buffer do |io|
        Cannon.encode(io, header)
        results.call io
      end
    end
  end
end
