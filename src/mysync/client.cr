require "./endpoint"
require "monocypher"
require "socket"
require "./network"
require "./package"

module MySync
  class UDPGameClient
    property symmetric_key

    def initialize(@endpoint : AbstractEndPoint, @address : Address)
      @socket = UDPSocket.new
      @socket.connect @address
      @raw_received = Bytes.new(MAX_PACKAGE_SIZE)
      @received_decrypted = Package.new(MAX_PACKAGE_SIZE)
      @tosend = Package.new(MAX_PACKAGE_SIZE)
      @tosend_header = @tosend.to_unsafe.as(UInt32*)
      @nonce = Crypto::Nonce.new
      @symmetric_key = Crypto::SymmetricKey.new
      @received_header = @raw_received.to_unsafe.as(UInt32*)
      spawn { reading_fiber }
    end

    # TODO - send packages asynchronously?
    private def package_received(package : Bytes)
      # first it decrypts and check
      return if package.size <= Crypto::OVERHEAD_SYMMETRIC
      @received_decrypted.size = package.size - Crypto::OVERHEAD_SYMMETRIC
      return unless Crypto.symmetric_decrypt(key: @symmetric_key, input: package, output: @received_decrypted.slice)
      # then pass to endpoint
      @endpoint.process_receive(@received_decrypted.slice)
    end

    private def reading_fiber
      loop do
        size, ip = @socket.receive(@raw_received)
        next if size < 4
        next if size > MAX_PACKAGE_SIZE
        next if @received_header.value != RIGHT_SIGN
        package_received @raw_received[4, size - 4]
      end
    end

    def send_data
      data = @endpoint.process_sending
      # then encrypt
      @nonce.reroll
      @tosend.size = data.size + Crypto::OVERHEAD_SYMMETRIC + 4
      Crypto.symmetric_encrypt(key: @symmetric_key, nonce: @nonce, input: data, output: @tosend.slice[4, @tosend.size - 4])
      # then send back
      @tosend_header.value = RIGHT_SIGN
      begin
        @socket.send(@tosend.slice, @address)
      rescue ex : Errno
        if ex.errno == Errno::ECONNREFUSED
          # well, message didn't pass
          p ex.inspect
        end
      end
    end
  end
end
