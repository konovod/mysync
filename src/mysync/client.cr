require "monocypher"
require "socket"
require "./endpoint"
require "./network"
require "./utils/package"
require "./payloads/rpc"
require "./payloads/lists"
require "./client_auth"

module MySync
  class UDPGameClient
    getter socket
    getter rpc_manager
    property debug_loss = false
    property autosend_delay : TimeDelta?
    property autologin_delay : TimeDelta?
    property disconnect_timeout : TimeDelta
    @time : TimeProvider

    def debug_str(string)
      puts "cli: #{string}"
    end

    def initialize(@endpoint : EndPoint, @address : Address)
      @socket = UDPSocket.new
      @socket.read_timeout = 1.seconds
      @socket.connect @address
      @raw_received = Bytes.new(MAX_RAW_SIZE)
      @received_decrypted = Package.new(MAX_PACKAGE_SIZE)
      @tosend = Package.new(MAX_RAW_SIZE)
      @tosend_header = @tosend.to_unsafe.as(UInt32*)
      @received_header = @raw_received.to_unsafe.as(UInt32*)
      @rpc_manager = Cannon::Rpc::Manager.new
      @endpoint.rpc_connection = CannonInterface.new(@endpoint, @rpc_manager)
      @endpoint.sync_lists = SyncListsManager.new
      @time = @endpoint.time
      @symmetric_key = Crypto::SymmetricKey.new
      @autosend_delay = nil
      @autologin_delay = nil
      @should_send = Channel(Nil).new
      @disconnect_timeout = TimeDelta.new(1*SECOND)
      @last_response = Time.new(0)

      spawn { reading_fiber }
      spawn { sending_fiber }
    end

    private def package_received(package : Bytes)
      # first it decrypts and check
      return if package.size <= Crypto::OVERHEAD_SYMMETRIC
      @received_decrypted.size = package.size - Crypto::OVERHEAD_SYMMETRIC
      return unless Crypto.decrypt(key: @symmetric_key, input: package, output: @received_decrypted.slice)
      @last_response = @time.current
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

    GOOD_SIGN = {
      AuthState::SendingLogin => RIGHT_LOGIN_SIGN,
      AuthState::SendingPass  => RIGHT_PASS_SIGN,
      AuthState::LoggedIn     => RIGHT_SIGN,
    }
    private def reading_fiber
      loop do
        debug_str "zzz"
        size, ip = try_receive
        if size < MIN_RAW_SIZE
          debug_str "size too small #{size}"
          next
        end
        if size > MAX_RAW_SIZE
          debug_str "size too big #{size}"
          next
        end
        package = @raw_received[4, size - 4]
        unless GOOD_SIGN[@auth_state] == @received_header.value
          debug_str "recv wrong header: #{@auth_state} => #{@received_header.value} need #{GOOD_SIGN[@auth_state]}"
          return
        end
        debug_str "recvd at #{@auth_state}"
        case @auth_state
        when AuthState::SendingLogin
          login_received(package)
        when AuthState::SendingPass
          pass_received(package)
        when AuthState::LoggedIn
          package_received (package)
        else
          # ignored
        end
      end
    end

    private def sending_fiber
      loop do
        @should_send.receive
        if @time.current - @last_response > @disconnect_timeout && @auth_state.restartable?
          @auth_state = AuthState::SendingLogin
        end
        debug_str "cli sending #{@auth_state}"
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

    @cur_delay = 0

    def timed_process
      @time.current += 1
      if @cur_delay <= 0
        return unless newdelay = get_autodelay
        @cur_delay = newdelay
        @should_send.send nil
      else
        @cur_delay -= 1
      end
    end

    def send_manually
      @should_send.send nil
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
