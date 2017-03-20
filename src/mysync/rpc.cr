require "cannon"
require "cannon/rpc"
require "./commands"

module MySync
  private alias ReceiveChannel = Channel(IO::Memory)

  # mostly copied from cannon/tcp_connection. optimize later?
  class CannonInterface < Cannon::Rpc::Connection
    getter manager

    def initialize(@endpoint : AbstractEndPoint, amanager : Cannon::Rpc::Manager)
      super(amanager)
      @handles = Hash(UInt8, Channel(Cannon::Rpc::Protocol::Header)).new
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
      # done = @endpoint.message_buffer.add_new({service_id: service_id, function_hash: function_hash, arguments: arguments})
      # io = done.receive
      # yield(io)
      # @endpoint.message_buffer.recycle done
    end

    # Like `call_remotely`, but doesn't request a response.  A response is
    # never requested and thus is never received.
    #
    # **Note**: This will also silence any error propagation from the remote
    # side back to the local side.
    #
    # This method **does not** block the current Fiber.
    def call_remotely(service_id : UInt32, function_hash : UInt32, arguments : Tuple?)
      send_call service_id, function_hash, arguments, 0u8, false
    end

    # Releases the remote *service_id*
    def release_remote_service(service_id : UInt32)
    end

    # Starts a read-loop, blocking the current Fiber.
    def run
    end
  end
end
