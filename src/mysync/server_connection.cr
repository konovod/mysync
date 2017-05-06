require "./endpoint"
require "monocypher"
require "socket"
require "./network"
require "./utils/package"
require "./payloads/rpc"

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

    # TODO - send packages asynchronously?

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

    private def process_password_packet
      # first it decrypts and check
      return unless auser = @user
      return if @received.size - Crypto::OVERHEAD_SYMMETRIC <= 0
      @received_decrypted.size = @received.size - Crypto::OVERHEAD_SYMMETRIC
      return unless Crypto.decrypt(
                      key: @symmetric_key,
                      input: @received.slice,
                      output: @received_decrypted.slice)
      # check password and create endpoint
      @last_message = @server.time.current
      hash = Crypto::SecretKey.from_bytes(@received_decrypted.slice)
      point = @server.authorize_2(auser, hash)
      unless point
        send_response wrong_pass_response(auser)
        return
      end
      @endpoint = point
      # now init common data
      point.rpc_connection = CannonInterface.new point, @server.rpc_manager
      point.sync_lists = @server.sync_lists
      # still send positive response, not usual
      # send_response point.process_sending
      send_response Bytes.new(1, 1u8), sign: RIGHT_PASS_SIGN
    end

    private def process_login_packet
      # here is encrypted packet with client public key as additional data
      return if @received.size < Crypto::PublicKey.size + Crypto::OVERHEAD_SYMMETRIC
      @received_decrypted.size = @received.size - Crypto::OVERHEAD_SYMMETRIC - Crypto::PublicKey.size
      akey = Crypto::PublicKey.from_bytes @received.slice[0, Crypto::PublicKey.size]
      login_key = @server.gen_key(akey)
      return unless Crypto.decrypt(
                      key: login_key,
                      input: @received.slice[Crypto::PublicKey.size, @received.size - Crypto::PublicKey.size],
                      output: @received_decrypted.slice)
      alogin = String.new(@received_decrypted.slice)
      auser = @server.authorize_1(alogin)
      unless auser
        send_response wrong_login_response(alogin), key: login_key, sign: RIGHT_LOGIN_SIGN
        login_key.reroll # wipe it
        return
      end
      @user = auser
      @last_message = @server.time.current
      # successful auth, send symmetric key and salt
      @symmetric_key.reroll
      response = Bytes.new(1 + Crypto::SymmetricKey.size + Crypto::Salt.size)
      response[0] = 1u8
      response[1, Crypto::SymmetricKey.size].copy_from @symmetric_key.to_slice
      response[1 + Crypto::SymmetricKey.size, Crypto::Salt.size].copy_from auser[:salt].to_slice
      send_response response, key: login_key, sign: RIGHT_LOGIN_SIGN
      login_key.reroll # wipe it
    end

    private def wrong_login_response(alogin)
      Bytes.new(1, 0u8)
    end

    private def wrong_pass_response(auser)
      Bytes.new(1, 0u8)
    end

    private def send_response(data, *, sign : UInt32 = RIGHT_SIGN, key : Crypto::SymmetricKey? = nil)
      unless key
        key = @symmetric_key
      end
      # then encrypt
      @tosend.size = data.size + Crypto::OVERHEAD_SYMMETRIC + 4
      @header.value = sign
      Crypto.encrypt(key: key, input: data, output: @tosend.slice[4, @tosend.size - 4])
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
