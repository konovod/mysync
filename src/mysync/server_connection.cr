require "./endpoint"
require "monocypher"
require "socket"
require "./network"
require "./package"

module MySync
  enum ConnectionCommand
    PacketReceived
    Close
  end

  class GameConnection
    getter socket
    getter received
    getter control
    getter last_message : Time
    getter endpoint : AbstractEndPoint?

    def initialize(@address : Address, @socket : UDPSocket,
                   @endpoint_factory : EndPointFactory, @secret_key : Crypto::SecretKey)
      @last_message = Time.now
      @received = Package.new(MAX_PACKAGE_SIZE)
      @received_decrypted = Package.new(MAX_PACKAGE_SIZE)
      @tosend = Package.new(MAX_PACKAGE_SIZE)
      @header = @tosend.to_unsafe.as(UInt32*)

      @control = Channel(ConnectionCommand).new
      @nonce = Crypto::Nonce.new
      @symmetric_key = Crypto::SymmetricKey.new
    end

    def should_die(at_time : Time) : Bool
      return true if at_time - @last_message > DISCONNECT_DELAY # timeout
      return false unless a = @endpoint                         # not authentificated
      a.requested_disconnect
    end

    # TODO - send packages asynchronously?

    def process_packet
      if point = @endpoint # connection already established
        # first it decrypts and check
        return if @received.size - Crypto::OVERHEAD_SYMMETRIC <= 0
        @received_decrypted.size = @received.size - Crypto::OVERHEAD_SYMMETRIC
        return unless Crypto.symmetric_decrypt(
                        key: @symmetric_key,
                        input: @received.slice,
                        output: @received_decrypted.slice)
        # then pass to endpoint
        @last_message = Time.now
        point.process_receive(@received_decrypted.slice)
        tosend_decrypted = point.process_sending
      else
        # here is anonymously encrypted packet with symmetric_key and auth data
        return if @received.size - Crypto::OVERHEAD_ANONYMOUS <= Crypto::SymmetricKey.size
        @received_decrypted.size = @received.size - Crypto::OVERHEAD_ANONYMOUS
        return unless Crypto.asymmetric_decrypt(
                        your_secret: @secret_key,
                        input: @received.slice,
                        output: @received_decrypted.slice)
        authdata = @received_decrypted.slice[Crypto::SymmetricKey.size, @received_decrypted.size - Crypto::SymmetricKey.size]
        received_key = @received_decrypted.slice[0, Crypto::SymmetricKey.size]
        tuple = @endpoint_factory.new_endpoint(authdata)
        return unless tuple
        @symmetric_key.to_slice.copy_from(received_key)
        @endpoint = tuple[:endpoint]
        # now send response
        tosend_decrypted = tuple[:response]
      end
      # then encrypt
      @nonce.reroll
      @tosend.size = tosend_decrypted.size + Crypto::OVERHEAD_SYMMETRIC + 4
      @header.value = RIGHT_SIGN
      Crypto.symmetric_encrypt(key: @symmetric_key, nonce: @nonce, input: tosend_decrypted, output: @tosend.slice[4, @tosend.size - 4])
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
        case cmd
        when ConnectionCommand::PacketReceived
          process_packet
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
