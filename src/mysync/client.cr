require "./endpoint"
require "monocypher"
require "socket"
require "./network"
require "./package"

module MySync
  class Client
    getter package
    property symmetric_key

    def initialize(@address : Address, @endpoint : AbstractEndPoint)
      @socket = UDPSocket.new
      @socket.connect @address
      @package = Package.new(MAX_PACKAGE_SIZE)
      @package_decrypted = Package.new(MAX_PACKAGE_SIZE)
      @nonce = Crypto::Nonce.new
      @symmetric_key = Crypto::SymmetricKey.new
    end

    # TODO - send packages asynchronously?
    def package_received
      # first it decrypts and check
      return if @package.size <= Crypto::OVERHEAD_SYMMETRIC
      @package_decrypted.size = @package.size - Crypto::OVERHEAD_SYMMETRIC
      return unless Crypto.symmetric_decrypt(key: @symmetric_key, input: @package.slice, output: @package_decrypted)
      # then pass to endpoint
      @endpoint.process_receive
    end
  end

  def send_data
    n = @endpoint.process_sending
    return if n <= 0
    # then encrypt
    @nonce.reroll
    Crypto.symmetric_encrypt(key: @symmetric_key, nonce: @nonce, input: @package_decrypted, output: @package)
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
