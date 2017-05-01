require "monocypher"
require "socket"
require "./endpoint"
require "./network"
require "./utils/package"
require "./payloads/rpc"
require "./payloads/lists"

module MySync
  enum AuthState
    NoData
    SendingLogin
    SendingPass
    LoginFailed
    LoggedIn

    def restartable?
      {SendingLogin, SendingPass, LoggedIn}.includes? self
    end
  end

  class UDPGameClient
    getter socket
    getter rpc_manager
    getter auth_state
    property debug_loss = false
    property autosend_delay : Time::Span?
    property autologin_delay : Time::Span?
    property disconnect_timeout : Time::Span
    @server_key : Crypto::PublicKey?
    @login_pass : (Crypto::SecretKey | String | Nil) = nil

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
      @login_key = Crypto::SymmetricKey.new
      @symmetric_key = Crypto::SymmetricKey.new
      @auth_state = AuthState::NoData
      @autosend_delay = nil
      @autologin_delay = nil
      @should_send = Channel(Nil).new
      @disconnect_timeout = 1.seconds
      @last_response = Time.now

      @login_name = ""
      @login_salt = Crypto::Salt.new

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

    private def try_send
      @socket.send(@tosend.slice, @address)
    rescue ex : Errno
      if ex.errno == Errno::ECONNREFUSED
        # well, message didn't pass
        p ex.inspect
      end
    end

    private def reading_fiber
      loop do
        size, ip = try_receive
        next if size < MIN_RAW_SIZE
        next if size > MAX_RAW_SIZE
        package = @raw_received[4, size - 4]
        case @auth_state
        when AuthState::SendingLogin
          login_received(package) if @received_header.value == RIGHT_LOGIN_SIGN
        when AuthState::SendingPass
          pass_received(package) if @received_header.value == RIGHT_SIGN
        when AuthState::LoggedIn
          package_received (package) if @received_header.value == RIGHT_SIGN
        else
          # ignore
        end
      end
    end

    private def sending_fiber
      loop do
        @should_send.receive
        if Time.now - @last_response > @disconnect_timeout && @auth_state.restartable?
          @auth_state = AuthState::SendingLogin
        end
        case @auth_state
        when AuthState::SendingLogin
          send_login
        when AuthState::SendingPass
          send_pass
        when AuthState::LoggedIn
          send_data
        end
      end
    end

    private def get_autodelay
      case @auth_state
      when AuthState::LoggedIn
        @autosend_delay
      else
        @autologin_delay
      end
    end

    private def auto_sending_fiber
      loop do
        if delay = get_autodelay
          t = Time.now
          @should_send.send nil
          sleep({delay - (Time.now - t), 0.01.seconds}.max)
        else
          sleep 0.1
        end
      end
    end

    def send_manually
      @should_send.send nil
    end

    def login(public_key : Crypto::PublicKey, alogin : String, pass) : Nil
      @server_key = public_key
      @login_name = alogin
      @login_pass = pass
      @auth_state = AuthState::SendingLogin
    end

    def wait_login : Bool
      raise "autologin_delay should be set" unless @autologin_delay
      @auth_state = MySync::AuthState::SendingLogin
      loop do
        Fiber.yield
        return true if @auth_state == MySync::AuthState::LoggedIn
        return false if @auth_state == MySync::AuthState::LoginFailed
      end
    end

    private def pass_received(package : Bytes)
      # first it decrypts and check
      return if package.size <= Crypto::OVERHEAD_SYMMETRIC
      @received_decrypted.size = package.size - Crypto::OVERHEAD_SYMMETRIC
      return unless Crypto.decrypt(key: @symmetric_key, input: package, output: @received_decrypted.slice)
      @last_response = Time.now
      if @received_decrypted.slice[0] == 1
        # all is fine, start listening
        @login_key.reroll
        @symmetric_key.to_slice.copy_from @received_decrypted.slice[1, Crypto::SymmetricKey.size]
        # data = Bytes.new(@received_decrypted.size - Crypto::SymmetricKey.size - 1)
        # data.copy_from @received_decrypted.slice[1 + Crypto::SymmetricKey.size, data.size]
        @last_response = Time.now
        @auth_state = AuthState::LoggedIn
        @endpoint.reset
      else
        # auth failed with a reason
        # data = Bytes.new(@received_decrypted.size - 1)
        # data.copy_from @received_decrypted.slice[1, data.size]
        @auth_state = AuthState::LoginFailed
      end
    end

    private def send_login
      secret_key = Crypto::SecretKey.new
      @login_key = Crypto::SymmetricKey.new(our_secret: secret_key, their_public: @server_key.not_nil!)
      our_public = Crypto::PublicKey.new(secret: secret_key)
      # we encrypt auth data and add our public key as additional data
      @tosend.size = 4 + Crypto::PublicKey.size + Crypto::OVERHEAD_SYMMETRIC + @login_name.bytes.size
      @tosend.slice[4, Crypto::PublicKey.size].copy_from our_public.to_slice
      Crypto.encrypt(
        key: @login_key,
        input: @login_name.to_slice,
        output: @tosend.slice[4 + Crypto::PublicKey.size, @login_name.size + Crypto::OVERHEAD_SYMMETRIC])
      # send it to server
      @tosend_header.value = RIGHT_LOGIN_SIGN
      try_send
    end

    private def send_pass
      pass_data = @login_pass
      case pass_data
      when Crypto::SecretKey
        data = pass_data.to_slice
      when String
        data = Crypto::SecretKey.new(password: pass_data, salt: @login_salt).to_slice
      else
        raise "no pass info provided"
      end
      # then encrypt
      @tosend.size = data.size + Crypto::OVERHEAD_SYMMETRIC + 4
      Crypto.encrypt(key: @symmetric_key, input: data, output: @tosend.slice[4, @tosend.size - 4])
      # then send back
      @tosend_header.value = RIGHT_PASS_SIGN
      try_send
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
        @login_salt = Crypto::Salt.from_bytes @received_decrypted.slice[1 + Crypto::SymmetricKey.size, Crypto::Salt.size]
        @last_response = Time.now
        @auth_state = AuthState::SendingPass
        # @endpoint.reset
      else
        # auth failed with a reason
        # data = Bytes.new(@received_decrypted.size - 1)
        # data.copy_from @received_decrypted.slice[1, data.size]
        @auth_state = AuthState::LoginFailed
      end
    end

    private def send_data
      data = @endpoint.process_sending
      # then encrypt
      @tosend.size = data.size + Crypto::OVERHEAD_SYMMETRIC + 4
      Crypto.encrypt(key: @symmetric_key, input: data, output: @tosend.slice[4, @tosend.size - 4])
      # then send back
      @tosend_header.value = RIGHT_SIGN
      return if @debug_loss
      try_send
    end
  end
end
