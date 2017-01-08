

module MySync

alias ClientID = Int32

enum Commands
  LOGIN = 1
  ECHO = 2
end

  abstract class Server

    def initialize
      #@logins = Hash.new(String, ClientID).new()
      #@clients = Hash(ClientID, ClientData).new()
    end

    abstract def send_static(io : IO)
    abstract def recv_static(io : IO)

    def process_request(io : IO)
      recv_static(io)
      send_static(io)
    end

  end

  module CachedIO
    include IO
    abstract def perform : Bool
  end

  abstract class Client

    def initialize(@io : CachedIO)
    end

    abstract def send_static
    abstract def recv_static

    def do_link()
      return unless @io
      send_static
      #TODO - asyncs
      return unless @io.perform
      recv_static
      #TODO - sync lists
      #TODO - asyncs
    end

  end



end
