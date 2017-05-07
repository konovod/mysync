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
    getter auth_state = AuthState::NoData
    @server_key : Crypto::PublicKey?
    @login_pass : (Crypto::SecretKey | String | Nil) = nil
    @login_name = ""
    @login_salt = Crypto::Salt.new
    @login_key = Crypto::SymmetricKey.new

    def save_hash
      case @login_pass
      when Crypto::SecretKey
        return @login_pass
      else
        return nil
      end
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
      # send_manually
      loop do
        Fiber.yield
        return true if @auth_state == MySync::AuthState::LoggedIn
        return false if @auth_state == MySync::AuthState::LoginFailed
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
        debug_str "starting KDF"
        key = Crypto::SecretKey.new(password: pass_data, salt: @login_salt)
        debug_str "KDF done"
        @login_pass = key
        data = key.to_slice
        # as it takes too much time anyway
        # @auth_state = AuthState::SendingLogin
        # send_manually
        # return
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

    private def pass_received(package : Bytes)
      # first it decrypts and check
      return if package.size <= Crypto::OVERHEAD_SYMMETRIC
      @received_decrypted.size = package.size - Crypto::OVERHEAD_SYMMETRIC
      return unless Crypto.decrypt(key: @symmetric_key, input: package, output: @received_decrypted.slice)
      debug_str "pass response: #{@received_decrypted.slice[0]}"
      @last_response = @time.current
      if @received_decrypted.slice[0] == 1
        # all is fine, start listening
        # data = Bytes.new(@received_decrypted.size - Crypto::SymmetricKey.size - 1)
        # data.copy_from @received_decrypted.slice[1 + Crypto::SymmetricKey.size, data.size]
        @auth_state = AuthState::LoggedIn
        @endpoint.reset
      else
        # auth failed with a reason
        # data = Bytes.new(@received_decrypted.size - 1)
        # data.copy_from @received_decrypted.slice[1, data.size]
        @auth_state = AuthState::LoginFailed
      end
    end

    def login_received(package) : Nil
      # decrypt it with symmetric_key
      return if package.size < Crypto::OVERHEAD_SYMMETRIC
      @received_decrypted.size = package.size - Crypto::OVERHEAD_SYMMETRIC
      return unless Crypto.decrypt(key: @login_key, input: package, output: @received_decrypted.slice)
      @last_response = @time.current
      debug_str "login response: #{@received_decrypted.slice[0]}"
      if @received_decrypted.slice[0] == 1
        # all is fine, copy symmetric_key and data to output and start listening
        @login_key.reroll
        @symmetric_key.to_slice.copy_from @received_decrypted.slice[1, Crypto::SymmetricKey.size]
        @login_salt = Crypto::Salt.from_bytes @received_decrypted.slice[1 + Crypto::SymmetricKey.size, Crypto::Salt.size]
        @auth_state = AuthState::SendingPass
        send_manually
      else
        # auth failed with a reason
        # data = Bytes.new(@received_decrypted.size - 1)
        # data.copy_from @received_decrypted.slice[1, data.size]
        @auth_state = AuthState::LoginFailed
      end
    end
  end
end
