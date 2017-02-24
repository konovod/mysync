require "./endpoint"
require "monocypher"
require "socket"
require "./network"
require "./package"

module MySync
  class Client
    property symmetric_key

    def initialize(@address : Address, @endpoint : AbstractEndPoint)
      @socket = UDPSocket.new
      @socket.connect @address
      @received = Package.new(MAX_PACKAGE_SIZE)
      @received_decrypted = Package.new(MAX_PACKAGE_SIZE)
      @tosend = Package.new(MAX_PACKAGE_SIZE)
      @nonce = Crypto::Nonce.new
      @symmetric_key = Crypto::SymmetricKey.new
    end

    # TODO - send packages asynchronously?
    private def package_received
      # first it decrypts and check
      return if @received.size <= Crypto::OVERHEAD_SYMMETRIC
      @received_decrypted.size = @received.size - Crypto::OVERHEAD_SYMMETRIC
      return unless Crypto.symmetric_decrypt(key: @symmetric_key, input: @received.slice, output: @received_decrypted.slice)
      # then pass to endpoint
      @endpoint.process_receive(@received_decrypted.slice)
    end
  end

  def send_data
    data = @endpoint.process_sending
    # then encrypt
    @nonce.reroll
    @tosend.size = data.size + Crypto::OVERHEAD_SYMMETRIC
    Crypto.symmetric_encrypt(key: @symmetric_key, nonce: @nonce, input: data, output: @tosend)
    # then send back
    begin
      @socket.send(@tosend, @address)
    rescue ex : Errno
      if ex.errno == Errno::ECONNREFUSED
        # well, message didn't pass
        p ex.inspect
      end
    end
  end
end
