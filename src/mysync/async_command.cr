require "cannon/rpc"

module MySync
  # TODO - later optimize to single buffer
  # record CmdOffset, offset : Int32, size : Int32

  class PackedCommand
    getter data

    def initialize(@id : UInt32)
      @data = IO::Memory.new
    end
  end

  class AsyncBuffer
    def initialize
      @cur_id = 0
      @commands = Array(PackedCommand).new
    end

    def push_command(service_id : UInt32, function_hash : UInt32, arguments : Tuple?)
      @cur_id += 1
      cmd = PackedCommand.new(@cur_id)
      Cannon.encode cmd.data, service_id
      Cannon.encode cmd.data, function_hash
      Cannon.encode cmd.data, arguments
      @commands << cmd
    end
  end

  abstract class AbstractEndPoint
    def add_command(service_id : UInt32, function_hash : UInt32, arguments : Tuple?)
      @async_tosend.push_command service_id, function_hash, arguments
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
    end

    # Like `call_remotely`, but doesn't request a response.  A response is
    # never requested and thus is never received.
    #
    # **Note**: This will also silence any error propagation from the remote
    # side back to the local side.
    #
    # This method **does not** block the current Fiber.
    def call_remotely(service_id : UInt32, function_hash : UInt32, arguments : Tuple?)
      @endpoint.add_command(service_id, function_hash, arguments)
    end

    # Releases the remote *service_id*
    def release_remote_service(service_id : UInt32)
    end

    # Starts a read-loop, blocking the current Fiber.
    def run
    end
  end
end
