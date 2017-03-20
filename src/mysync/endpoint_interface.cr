require "./commands"
require "./rpc"

module MySync
  abstract class AbstractEndPoint
    getter requested_disconnect : Bool
    getter cmd_buffer : CommandBuffer
    property rpc_connection : CannonInterface?

    def initialize
      @requested_disconnect = false
      @cmd_buffer = CommandBuffer.new
    end

    abstract def process_receive(data : Bytes) : Nil
    abstract def process_sending : Bytes

    def on_disconnect
    end
  end

  module EndPointFactory
    abstract def new_endpoint(authdata : Bytes) : {endpoint: AbstractEndPoint, response: Bytes}?
    abstract def on_connecting(ip : Address)
    abstract def on_disconnecting(ip : Address, ex : Exception?)
  end
end
