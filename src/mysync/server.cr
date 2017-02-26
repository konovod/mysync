require "./endpoint_interface"
require "monocypher"
require "socket"
require "./network"
require "./package"
require "./server_connection"

module MySync
  class UDPGameServer
    @header : UInt32*

    def initialize(@endpoint_factory : EndPointFactory, @port : Int32, @secret_key : Crypto::SecretKey)
      @connections = Hash(AddressHash, GameConnection).new
      @banned = Set(Address).new
      @socket = UDPSocket.new(Socket::Family::INET)
      @socket.bind("0.0.0.0", @port)
      @single_buffer = Bytes.new(MAX_PACKAGE_SIZE)
      @header = @single_buffer.to_unsafe.as(UInt32*)
      spawn { listen_fiber }
      spawn { timed_fiber }
    end

    def n_clients
      @connections.size
    end

    private def get_connection(ip : Address) : GameConnection
      # cleanup_connections
      conn1 = @connections[MySync.addr_hash(ip)]?
      return conn1 if conn1
      p "adding connection #{ip}"
      conn2 = GameConnection.new(ip, @socket, @endpoint_factory, @secret_key)
      @connections[MySync.addr_hash(ip)] = conn2
      spawn { conn2.execute }
      return conn2
    end

    private def listen_fiber
      loop do
        size, ip = @socket.receive(@single_buffer)
        next if size < 4
        next if size > MAX_PACKAGE_SIZE
        next if @header.value != RIGHT_SIGN
        next if @banned.includes? ip
        conn = get_connection(ip)
        conn.received.size = size - 4
        conn.received.slice.copy_from @single_buffer[4, size - 4]
        conn.control.send(ConnectionCommand::PacketReceived)
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
