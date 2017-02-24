require "./endpoint"
require "monocypher"
require "socket"
require "./network"

module MySync
  enum ConnectionCommand
    Packet
    Close
  end

  class GameConnection
    getter received
    getter control
    getter last_message : Time
    getter symmetric_key
    @endpoint : AbstractEndPoint?

    def initialize(@address : Address, @socket : UDPSocket,
                   @endpoint_factory : EndPointFactory)
      @last_message = Time.now
      @received = Package.new(MAX_PACKAGE_SIZE)
      @received_decrypted = Package.new(MAX_PACKAGE_SIZE)
      @tosend_decrypted = Package.new(MAX_PACKAGE_SIZE)
      @tosend = Package.new(MAX_PACKAGE_SIZE)

      @control = Channel(ConnectionCommand).new
      @nonce = Crypto::Nonce.new
      @symmetric_key = Crypto::SymmetricKey.new
    end

    def should_die(at_time : Time)
      return true if at_time - @last_message > DISCONNECT_DELAY # timeout
      return false unless a = @endpoint                         # not authentificated
      a.requested_disconnect
    end

    # TODO - send packages asynchronously?

    def process_packet
      point = @endpoint
      unless point
        # TODO - authentification
        userid = 2
        point = @endpoint_factory.new_endpoint(userid, @received_decrypted.base, @tosend_decrypted.base)
        @endpoint = point
      end
      # first it decrypts and check
      return if @received.size - Crypto::OVERHEAD_SYMMETRIC <= 0
      @received_decrypted.size = @received.size - Crypto::OVERHEAD_SYMMETRIC
      return unless Crypto.symmetric_decrypt(key: @symmetric_key, input: @received.slice, output: @received_decrypted.slice)
      # then pass to endpoint
      @last_message = Time.now
      point.process_receive
      n = point.process_sending
      return if n <= 0
      @tosend_decrypted.size = n
      # then encrypt
      @nonce.reroll
      @tosend.size = n + Crypto::OVERHEAD_SYMMETRIC
      Crypto.symmetric_encrypt(key: @symmetric_key, nonce: @nonce, input: @tosend_decrypted.slice, output: @tosend.slice)
      # then send back
      begin
        @socket.send(@tosend.slice, @address)
      rescue ex : Errno
        if ex.errno == Errno::ECONNREFUSED
          # well, message didn't pass
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
      spawn { listen_fiber }
      spawn { timed_fiber }
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
          spawn { conn.execute }
        end
        conn.received.size = size - 4
        conn.received.slice.copy_from @single_buffer[4, size - 4]
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
