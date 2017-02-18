require "./interface"
require "monocypher"
require "socket"

module MySync

alias Address = Socket::IPAddress
RIGHT_SIGN = 0xC4AC7BE
DISCONNECT_DELAY = Time::Span.new(0,0,1)


enum ConnectionCommand
  Packet
  Close
end

class GameConnection
  getter package
  getter control
  getter last_message : Time
  getter requested_disconnect : Bool
  def initialize(@address : Address, @socket : UDPSocket)
    @last_message = Time.now
    @requested_disconnect = false
    @package = Bytes.new(MAX_PACKAGE_SIZE)
    @control = Channel(ConnectionCommand).new
  end

  def process_packet
    #TODO - actual work

    #if something something
    @last_message = Time.now
  end

  def execute
    loop do
      cmd = @control.receive
      case ConnectionCommand
      when ConnectionCommand::Packet
        process_packet
      when ConnectionCommand::Close
        return
      end
    end
  end

end

class UDPGameServer
  @header : UInt32*
  def initialize(@port : Int32)
    @connections = Hash(Address, GameConnection).new
    @banned = Set(Address).new
    @socket = UDPSocket.new(Socket::Family::INET)
    @socket.bind("localhost", @port)
    @single_buffer = Bytes.new(MAX_PACKAGE_SIZE)
    @header = @single_buffer.to_unsafe.as(UInt32*)
    spawn {listen_fiber}
    spawn {timed_fiber}
  end

  private def listen_fiber
    loop do
      size, ip = @socket.receive(@single_buffer)
      next if size < 4
      next if size > MAX_PACKAGE_SIZE
      next if @header.value != RIGHT_SIGN
      next if @banned.includes? ip
      conn = @connections[ip]
      unless conn
        conn = GameConnection.new(ip, @socket)
        @connections[ip] = conn
        spawn {conn.execute}
      end
      conn.package.copy_from @single_buffer[4, size-4]
      conn.control.send(ConnectionCommand::Packet)
    end
  end

  private def timed_fiber
    loop do
      time = Time.now
      @connections.reject! do |addr, conn|
        result = conn.requested_disconnect || time - conn.last_message > DISCONNECT_DELAY
        conn.control.send(ConnectionCommand::Close) if result
        result
      end
      sleep(1)
    end
  end

  def game_logic
  end


end



end

srv = MySync::UDPGameServer.new(12345)
