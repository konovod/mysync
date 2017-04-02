require "monocypher"
require "socket"
require "./endpoint"
require "./network"
require "./package"
require "./rpc"

module MySync
  enum LoginState
    NoData
    NotLoggedIn
    LoggedIn
  end

  class UDPGameClient
    getter socket
    getter rpc_manager
    property debug_loss = false
    property autosend_delay : Time::Span?
    property disconnect_timeout : Time::Span
    @server_key : Crypto::PublicKey?

    def initialize(@endpoint : EndPoint, @address : Address)
      @socket = UDPSocket.new
      @socket.read_timeout = Time::Span.new(0, 0, 1)
      @socket.connect @address
      @raw_received = Bytes.new(MAX_RAW_SIZE)
      @received_decrypted = Package.new(MAX_PACKAGE_SIZE)
      @tosend = Package.new(MAX_RAW_SIZE)
      @tosend_header = @tosend.to_unsafe.as(UInt32*)
      @received_header = @raw_received.to_unsafe.as(UInt32*)
      @rpc_manager = Cannon::Rpc::Manager.new
      @endpoint.rpc_connection = CannonInterface.new(@endpoint, @rpc_manager)
      @endpoint.sync_lists = SyncListsManager.new
      @login_data = Bytes.new(0)
      @login_key = Crypto::SymmetricKey.new
      @symmetric_key = Crypto::SymmetricKey.new
      @login_complete = Channel(Bytes).new
      @logged = LoginState::NoData
      @autosend_delay = nil
      @should_send = Channel(Nil).new
      @disconnect_timeout = 1.seconds
      @last_response = Time.now
      spawn { reading_fiber }
      spawn { sending_fiber }
      spawn { auto_sending_fiber }
    end

    private def package_received(package : Bytes)
      # first it decrypts and check
      return if package.size <= Crypto::OVERHEAD_SYMMETRIC
      @received_decrypted.size = package.size - Crypto::OVERHEAD_SYMMETRIC
      return unless Crypto.decrypt(key: @symmetric_key, input: package, output: @received_decrypted.slice)
      @last_response = Time.now
      # then pass to endpoint
      @endpoint.process_receive(@received_decrypted.slice)
    end

    private def try_receive
      @socket.receive(@raw_received)
    rescue
      {0, nil}
    end

    private def reading_fiber
      loop do
        size, ip = try_receive
        next if size < MIN_RAW_SIZE
        next if size > MAX_RAW_SIZE
        package = @raw_received[4, size - 4]
        case @logged
        when LoginState::NotLoggedIn
          login_received(package) if @received_header.value == RIGHT_LOGIN_SIGN
        when LoginState::LoggedIn
          package_received (package) if @received_header.value == RIGHT_SIGN
        else
          # ignore
        end
      end
    end

    private def sending_fiber
      loop do
        @should_send.receive
        @logged = LoginState::NotLoggedIn if Time.now - @last_response > @disconnect_timeout
        case @logged
        when LoginState::NotLoggedIn
          send_login
        when LoginState::LoggedIn
          send_data
        end
      end
    end

    private def auto_sending_fiber
      loop do
        if delay = @autosend_delay
          @should_send.send nil
          sleep delay
        else
          sleep 0.1
        end
      end
    end

    def send_manually
      @should_send.send nil
    end

    def login(public_key : Crypto::PublicKey, authdata : Bytes) : Nil
      @server_key = public_key
      @login_data = authdata
      @logged = LoginState::NotLoggedIn
    end

    def wait_login : Bytes
      raise "autosend_delay should be set" unless @autosend_delay
      @login_complete.receive
    end

    private def send_login
      secret_key = Crypto::SecretKey.new
      @login_key = Crypto::SymmetricKey.new(our_secret: secret_key, their_public: @server_key.not_nil!)
      our_public = Crypto::PublicKey.new(secret: secret_key)
      # we encrypt auth data and add our public key as additional data
      @tosend.size = 4 + Crypto::PublicKey.size + Crypto::OVERHEAD_SYMMETRIC + @login_data.size
      @tosend.slice[4, Crypto::PublicKey.size].copy_from our_public.to_slice
      Crypto.encrypt(
        key: @login_key,
        input: @login_data,
        #        additional: our_public.to_slice,
        output: @tosend.slice[4 + Crypto::PublicKey.size, @login_data.size + Crypto::OVERHEAD_SYMMETRIC])
      # send it to server
      @tosend_header.value = RIGHT_LOGIN_SIGN
      begin
        @socket.send(@tosend.slice, @address)
      rescue ex : Errno
        return nil
      end
    end

    def login_received(package) : Nil
      # decrypt it with symmetric_key
      return if package.size < Crypto::OVERHEAD_SYMMETRIC
      @received_decrypted.size = package.size - Crypto::OVERHEAD_SYMMETRIC
      return unless Crypto.decrypt(key: @login_key, input: package, output: @received_decrypted.slice)
      if @received_decrypted.slice[0] == 1
        # all is fine, copy symmetric_key and data to output and start listening
        @login_key.reroll
        @symmetric_key.to_slice.copy_from @received_decrypted.slice[1, Crypto::SymmetricKey.size]
        data = Bytes.new(@received_decrypted.size - Crypto::SymmetricKey.size - 1)
        data.copy_from @received_decrypted.slice[1 + Crypto::SymmetricKey.size, data.size]
        @last_response = Time.now
        @logged = LoginState::LoggedIn
        @endpoint.reset
      else
        # auth failed with a reason
        data = Bytes.new(@received_decrypted.size - 1)
        data.copy_from @received_decrypted.slice[1, data.size]
      end
      @login_complete.send data
    end

    private def send_data
      data = @endpoint.process_sending
      # then encrypt
      @tosend.size = data.size + Crypto::OVERHEAD_SYMMETRIC + 4
      Crypto.encrypt(key: @symmetric_key, input: data, output: @tosend.slice[4, @tosend.size - 4])
      # then send back
      @tosend_header.value = RIGHT_SIGN
      return if @debug_loss
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
