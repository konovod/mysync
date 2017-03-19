require "cannon"
require "cannon/rpc"
require "./commands"

module MySync
  private alias ReceiveChannel = Channel(IO::Memory)

  # private alias CallTuple = {service_id: UInt32, function_hash: UInt32, arguments: Tuple?}

  # private record CommandHeader,
  #   id : Uint32,
  #   need_answer : Bool,
  #   service_id : UInt32,
  #   function_hash : UInt32
  class CannonInterface < Cannon::Rpc::Connection
    getter manager

    def initialize(@endpoint : AbstractEndPoint, amanager : Cannon::Rpc::Manager)
      super(amanager)
      # @channels = Array(ReceiveChannel).new
    end

    #
    # def add_new(call : CallTuple)
    #   @last_sent_id += 1
    #   chan = @channels.pop? || ReceiveChannel.new
    #   cmd = Command.new(@last_sent_id, call, chan)
    #   push cmd
    #   return chan
    # end
    #
    # def add_no_answer(call : CallTuple) : Nil
    #   @last_sent_id += 1
    #   cmd = Command.new(@last_sent_id, call, nil)
    #   cmd.complete_channel = @channels.pop? || ReceiveChannel.new
    #   push cmd
    # end
    #

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
      # @endpoint.message_buffer.add_no_answer({service_id: service_id, function_hash: function_hash, arguments: arguments})
    end

    # Releases the remote *service_id*
    def release_remote_service(service_id : UInt32)
    end

    # Starts a read-loop, blocking the current Fiber.
    def run
    end
  end
end
