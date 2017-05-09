require "./endpoint"
require "monocypher"
require "socket"
require "./network"
require "./utils/package"
require "./payloads/rpc"
require "./server_auth"

module MySync
  enum ConnectionCommand
    LoginReceived
    PasswordReceived
    PacketReceived
    Close
  end

  class GameConnection
    getter socket
    getter received
    getter control
    getter last_message : Time
    getter endpoint : EndPoint?
    getter user : AuthData?
    getter can_send = Channel(Nil).new

    def debug_str(string)
      # puts "srv: #{string}"
    end

    def initialize(@address : Address, @socket : UDPSocket,
                   @server : GameServer)
      @last_message = @server.time.current
      @received = Package.new(MAX_RAW_SIZE) # TODO - remove small tail?
      @received_decrypted = Package.new(MAX_PACKAGE_SIZE)
      @tosend = Package.new(MAX_RAW_SIZE)
      @header = @tosend.to_unsafe.as(UInt32*)

      @control = Channel(ConnectionCommand).new
      @symmetric_key = Crypto::SymmetricKey.new
    end

    def should_die(at_time : Time) : Bool
      return true if at_time - @last_message > @server.disconnect_delay # timeout
      return false unless a = @endpoint                                 # not authentificated
      a.requested_disconnect
    end

    private def process_data_packet
      return unless point = @endpoint # connection must be already established
      # first it decrypts and check
      return if @received.size - Crypto::OVERHEAD_SYMMETRIC <= 0
      @received_decrypted.size = @received.size - Crypto::OVERHEAD_SYMMETRIC
      return unless Crypto.decrypt(
                      key: @symmetric_key,
                      input: @received.slice,
                      output: @received_decrypted.slice)
      # then pass to endpoint
      @last_message = @server.time.current
      point.process_receive(@received_decrypted.slice)
      send_response point.process_sending
    end

    private def send_response(data : Bytes, *, sign : UInt32 = RIGHT_SIGN, key : Crypto::SymmetricKey? = nil)
      spawn do
        @can_send.receive
        actual_send_response(data, sign: sign, key: key)
      end
    end

    private def actual_send_response(data, *, sign : UInt32 = RIGHT_SIGN, key : Crypto::SymmetricKey? = nil)
      # then encrypt
      @tosend.size = data.size + Crypto::OVERHEAD_SYMMETRIC + 4
      @header.value = sign
      Crypto.encrypt(key: key || @symmetric_key, input: data, output: @tosend.slice[4, @tosend.size - 4])
      key.reroll if key
      # then send back
      return if @server.debug_loss
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
        case cmd
        when ConnectionCommand::LoginReceived
          process_login_packet
        when ConnectionCommand::PasswordReceived
          process_password_packet
        when ConnectionCommand::PacketReceived
          process_data_packet
        when ConnectionCommand::Close
          if point = @endpoint
            point.on_disconnect
          end
          return
        end
      end
    end
  end
end
