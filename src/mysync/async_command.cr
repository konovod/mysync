require "cannon"
require "cannon/rpc"

module MySync
  # TODO - later optimize to single buffer
  # record PackedCommand, offset : Int32, size : Int32
  alias ReceiveChannel = Channel(IO::Memory)

  class PackedCommand
    getter data
    property complete_channel : ReceiveChannel?

    def initialize(service_id : UInt32, function_hash : UInt32, arguments : Tuple?)
      @data = IO::Memory.new
      Cannon.encode @data, service_id
      Cannon.encode @data, function_hash
      Cannon.encode @data, arguments
    end
  end

  class AsyncBuffer
    def initialize
      @commands = Array(PackedCommand).new
      @channels = Array(ReceiveChannel).new
    end

    def push(cmd)
      cmd.complete_channel = @channels.pop? || ReceiveChannel.new
      @commands << cmd
      return cmd.complete_channel
    end

    def recycle(channel)
      @channels << channel
    end

    def push_noanswer(cmd) : Nil
      @commands << cmd
    end

    def pop(remaining_size : Int32) : PackedCommand?
      result = @commands.find { |cmd| cmd.data.size <= remaining_size }
      @commands.delete result if result
      result
    end
  end

  class CannonInterface < Cannon::Rpc::Connection
    getter manager

    def initialize(@endpoint : AbstractEndPoint, amanager : Cannon::Rpc::Manager)
      super(amanager)
    end

    # Calls the function (through *function_hash*) on *service_id* using
    # *arguments*.  Yields an `IO` when the response was received and must
    # be read from it using `Cannon.decode`.  If a remote error was
    # encountered, the block is *not* called, and is raised locally.
    #
    # This method blocks the current Fiber.
    def call_remotely(service_id : UInt32, function_hash : UInt32, arguments : Tuple?, &block : IO -> _)
      done = @endpoint.async_buffer.push(PackedCommand.new(service_id, function_hash, arguments)).not_nil!
      io = done.receive
      yield(io)
      @endpoint.async_buffer.recycle done
    end

    # Like `call_remotely`, but doesn't request a response.  A response is
    # never requested and thus is never received.
    #
    # **Note**: This will also silence any error propagation from the remote
    # side back to the local side.
    #
    # This method **does not** block the current Fiber.
    def call_remotely(service_id : UInt32, function_hash : UInt32, arguments : Tuple?)
      @endpoint.async_buffer.push_noanswer PackedCommand.new(service_id, function_hash, arguments)
    end

    # Releases the remote *service_id*
    def release_remote_service(service_id : UInt32)
    end

    # Starts a read-loop, blocking the current Fiber.
    def run
    end
  end
end
