require "./endpoint"
require "monocypher"
require "socket"
require "./network"
require "./package"
require "./payloads/rpc"

module MySync
  enum ConnectionCommand
    LoginReceived
    PacketReceived
    Close
  end

  class GameConnection
    getter socket
    getter received
    getter control
    getter last_message : Time
    getter endpoint : EndPoint?

    def initialize(@address : Address, @socket : UDPSocket,
                   @endpoint_factory : EndPointFactory,
                   @server : UDPGameServer)
      @last_message = Time.now
      @received = Package.new(MAX_RAW_SIZE) # TODO - remove small tail?
      @received_decrypted = Package.new(MAX_PACKAGE_SIZE)
      @tosend = Package.new(MAX_RAW_SIZE)
      @header = @tosend.to_unsafe.as(UInt32*)

      @control = Channel(ConnectionCommand).new
      @login_key = Crypto::SymmetricKey.new
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
      @last_message = Time.now
      point.process_receive(@received_decrypted.slice)
      send_response point.process_sending, is_login: false
    end

    private def process_login_packet
      # here is encrypted packet with client public key as additional data
      return if @received.size < Crypto::PublicKey.size + Crypto::OVERHEAD_SYMMETRIC
      @received_decrypted.size = @received.size - Crypto::OVERHEAD_SYMMETRIC - Crypto::PublicKey.size
      akey = Crypto::PublicKey.from_bytes @received.slice[0, Crypto::PublicKey.size]
      @login_key = @server.gen_key(akey)
      return unless Crypto.decrypt(
                      key: @login_key,
                      input: @received.slice[Crypto::PublicKey.size, @received.size - Crypto::PublicKey.size],
                      # additional: @received.slice[0, Crypto::PublicKey.size],
                      output: @received_decrypted.slice)
      tuple = @endpoint_factory.new_endpoint(@received_decrypted.slice)
      if point = tuple[:endpoint] # successful auth
        @symmetric_key.reroll
        @endpoint = point
        # now init common data
        point.rpc_connection = CannonInterface.new point, @endpoint_factory.rpc_manager
        point.sync_lists = @endpoint_factory.sync_lists
        response = Bytes.new(1 + Crypto::SymmetricKey.size + tuple[:response].size)
        response[0] = 1u8
        response[1, Crypto::SymmetricKey.size].copy_from @symmetric_key.to_slice
        response[1 + Crypto::SymmetricKey.size, tuple[:response].size].copy_from tuple[:response]
        send_response response, is_login: true
      else # not successful, with response
        response = Bytes.new(1 + tuple[:response].size)
        response[0] = 0u8
        response[1, tuple[:response].size].copy_from tuple[:response]
        send_response response, is_login: true
      end
      # and send response
    end

    private def send_response(data, *, is_login : Bool)
      # then encrypt
      @tosend.size = data.size + Crypto::OVERHEAD_SYMMETRIC + 4
      if is_login
        @header.value = RIGHT_LOGIN_SIGN
        Crypto.encrypt(key: @login_key, input: data, output: @tosend.slice[4, @tosend.size - 4])
        @login_key.reroll
      else
        @header.value = RIGHT_SIGN
        Crypto.encrypt(key: @symmetric_key, input: data, output: @tosend.slice[4, @tosend.size - 4])
      end
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
