require "./endpoint"
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
  @endpoint : AbstractEndPoint?
  def initialize(@address : Address, @socket : UDPSocket,
                  @endpoint_factory : EndPointFactory
                  )
    @last_message = Time.now
    @package = Bytes.new(MAX_PACKAGE_SIZE)
    @package_decrypted = Bytes.new(MAX_PACKAGE_SIZE)
    @tosend_decrypted = Bytes.new(MAX_PACKAGE_SIZE)
    @tosend = Bytes.new(MAX_PACKAGE_SIZE)
    @control = Channel(ConnectionCommand).new
    @nonce = Crypto::Nonce.new
    @symmetric_key = Crypto::SymmetricKey.new
  end

  def should_die(at_time : Time)
    return true if at_time - @last_message > DISCONNECT_DELAY  #timeout
    return false unless a = @endpoint #not authentificated
    a.requested_disconnect
  end

  #TODO - send packages asynchronously?


  def process_packet
    point = @endpoint
    unless point
        #TODO - authentification
        userid = 2
        point = @endpoint_factory.new_endpoint(userid, @package_decrypted, @tosend_decrypted)
        @endpoint = point
    end
    #first it decrypts and check
    return unless Crypto.symmetric_decrypt(key: @symmetric_key, input: @package, output: @package_decrypted)
    #then pass to endpoint
    @last_message = Time.now
    point.process_receive
    n = point.process_sending
    return if n<=0
    #then encrypt
    @nonce.reroll
    Crypto.symmetric_encrypt(key: @symmetric_key, nonce: @nonce, input: @tosend_decrypted, output: @tosend)
    #then send back
    begin
      @socket.send(@tosend, @address)
    rescue ex : Errno
      if ex.errno == Errno::ECONNREFUSED
        #well, message didn't pass
        p ex.inspect
      end
    end
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
  def initialize(@endpoint_factory : EndPointFactory, @port : Int32)
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
        conn = GameConnection.new(ip, @socket, @endpoint_factory)
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
        result = conn.should_die(time)
        conn.control.send(ConnectionCommand::Close) if result
        result
      end
      sleep(1)
    end
  end

end



end
