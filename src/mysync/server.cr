require "./endpoint"
require "monocypher"
require "socket"
require "./network"
require "./package"
require "./server_connection"

module MySync
  class UDPGameServer
    @header : UInt32*
    property disconnect_delay

    def initialize(@endpoint_factory : EndPointFactory, @port : Int32, @secret_key : Crypto::SecretKey)
      @disconnect_delay = Time::Span.new(0, 0, 1)
      @connections = Hash(AddressHash, GameConnection).new
      @banned = Set(Address).new
      @socket = UDPSocket.new(Socket::Family::INET)
      @socket.bind("0.0.0.0", @port)
      @single_buffer = Bytes.new(MAX_RAW_SIZE)
      @header = @single_buffer.to_unsafe.as(UInt32*)
      spawn { listen_fiber }
      spawn { timed_fiber }
    end

    def gen_key(client_public : Crypto::PublicKey) : Crypto::SymmetricKey
      Crypto::SymmetricKey.new(our_secret: @secret_key, their_public: client_public)
    end

    def n_clients
      @connections.size
    end

    private def get_connection(ip : Address) : GameConnection
      # cleanup_connections
      conn1 = @connections[MySync.addr_hash(ip)]?
      return conn1 if conn1
      @endpoint_factory.on_connecting(ip)
      conn2 = GameConnection.new(ip, @socket, @endpoint_factory, self)
      @connections[MySync.addr_hash(ip)] = conn2
      spawn do
        begin
          conn2.execute
          @endpoint_factory.on_disconnecting(ip, nil)
        rescue ex
          @endpoint_factory.on_disconnecting(ip, ex)
        ensure
          @connections.delete(MySync.addr_hash(ip))
        end
      end
      return conn2
    end

    private def listen_fiber
      loop do
        size, ip = @socket.receive(@single_buffer)
        next if size < MIN_RAW_SIZE
        next if size > MAX_RAW_SIZE
        next if @header.value != RIGHT_SIGN && @header.value != RIGHT_LOGIN_SIGN
        next if @banned.includes? ip
        conn = get_connection(ip)
        conn.received.size = size - 4
        conn.received.slice.copy_from @single_buffer[4, size - 4]
        if @header.value == RIGHT_SIGN
          conn.control.send(ConnectionCommand::PacketReceived)
        else
          conn.control.send(ConnectionCommand::LoginReceived)
        end
      end
    end

    private def cleanup_connections
      time = Time.now
      @connections.delete_if do |addr, conn|
        dead = conn.should_die(time)
        conn.control.send(ConnectionCommand::Close) if dead
        dead
      end
    end

    private def timed_fiber
      loop do
        sleep(0.2)
        cleanup_connections
      end
    end
  end
end
