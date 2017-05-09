require "spec"
require "cannon"
require "../src/mysync"
require "../src/mysync/server"
require "../src/mysync/endpoint"
require "../src/mysync/client"

class SpecLogger
  @@events = [] of String

  def self.log_srv(s : String)
    @@events << "SERVER: #{s}"
  end

  def self.log_cli(s : String)
    @@events << "CLIENT: #{s}"
  end

  def self.dump_events
    r = @@events.clone
    @@events.clear
    r
  end
end

struct TestClientInput
  include Cannon::Auto
  property num : Int32
  property data : String

  def initialize
    @num = -1
    @data = ""
  end

  def initialize(@num, @data)
  end
end

struct TestServerOutput
  include Cannon::Auto
  property all_data

  def initialize
    @all_data = StaticArray(String, 16).new("")
  end

  def initialize(@all_data)
  end
end

class TestUserContext < MySync::EndPoint
  set_local_sync(TestServerOutput)
  set_remote_sync(TestClientInput)
  property verbose : Bool = false

  def on_disconnect
    SpecLogger.log_srv "user disconnected: #{@username}"
  end

  def on_received_package
    SpecLogger.log_srv "received" if @verbose
    @server.state.all_data[@remote_sync.num] = @remote_sync.data if @remote_sync.num >= 0
  end

  def before_sending_package
    SpecLogger.log_srv "sending" if @verbose
    @local_sync = @server.state
  end

  def initialize(@server : TestServer, @user : Int32, @username : String)
    super(@server.time)
  end
end

class TestUsers < MySync::UsersStorage
  property registration_open = false
  getter data = Hash(String, MySync::UserData).new

  def add_user(login : String, salt : Crypto::Salt, hash : Crypto::SecretKey)
    @data[login] = {salt: salt, hash: hash, id: @data.size}
  end

  def find_user(login : String) : MySync::UserData?
    if found = @data[login]?
      SpecLogger.log_srv "logged in: #{login}"
      return found
    else
      SpecLogger.log_srv "failed to log in: #{login}"
      return nil
    end
  end

  def allow_registration(login : String)
    @registration_open
  end

  def demo_add_user(login, pass)
    salt = Crypto::Salt.new
    # hash = Crypto::SecretKey.new(password: pass, salt: salt)
    hash = Crypto::SecretKey.new
    add_user login, salt, hash
    return hash
  end
end

class TestServer < MySync::GameServer
  property state = TestServerOutput.new
  getter test_endpoint : MySync::EndPoint?

  def new_endpoint(user : MySync::UserID, time : MySync::TimeProvider) : MySync::EndPoint
    TestUserContext.new(self, user % 16, "person#{user + 1}").tap { |pt| @test_endpoint = pt }
  end

  def on_connecting(ip : Socket::IPAddress)
    SpecLogger.log_srv "adding connection"
  end

  def on_disconnecting(ip : Socket::IPAddress, ex : Exception?)
    if ex
      p "connection #{ip} raised #{ex}"
      SpecLogger.log_srv "connection raised"
    else
      SpecLogger.log_srv "connection complete"
    end
  end
end

class TestClientEndpoint < MySync::EndPoint
  set_local_sync TestClientInput
  set_remote_sync TestServerOutput

  property benchmark : Int32 = 0
  getter benchmark_complete = Channel(Nil).new
  property verbose : Bool = true

  def on_received_package
    SpecLogger.log_cli "received" if @verbose
    if @benchmark > 0
      # p "received #{@benchmark}"
      @benchmark -= 1
      @benchmark_complete.send(nil) if @benchmark == 0
    end
  end

  def before_sending_package
    SpecLogger.log_cli "sending" if @verbose
  end
end

class TestingClient < MySync::UDPGameClient
  def endpoint=(point)
    @endpoint = point
  end
end

class TimeEmulation
  @@active = false
  @@stopped = Channel(Nil).new

  def self.timed_fiber(items)
    loop do
      unless @@active
        @@stopped.send(nil)
        break
      end
      items.each &.timed_process
      Fiber.yield
    end
  end

  def self.start(items)
    @@active = true
    spawn { timed_fiber(items) }
    Fiber.yield
  end

  def self.stop
    @@active = false
    @@stopped.receive
  end
end

def one_exchange(cli, udp_cli, srv)
  udp_cli.send_manually
  Fiber.yield
  srv.timed_process
  Fiber.yield
  udp_cli.timed_process
  # skip_time({udp_cli, srv}, 1)
end

def skip_time(items, n)
  n.times do
    Fiber.yield
    items.each &.timed_process
  end
end

def one_login(udp_cli, srv)
  udp_cli.autologin_delay = 10
  TimeEmulation.start({udp_cli, srv})
  answer = udp_cli.wait_login
  TimeEmulation.stop
  udp_cli.autologin_delay = nil
  return answer
end

def do_login(udp_cli, srv, users, public_key, login)
  hash = users.demo_add_user(login, login)
  udp_cli.login(public_key, login, hash)
  one_login(udp_cli, srv)
end

def make_test_pair(crunch)
  secret_key = Crypto::SecretKey.new
  public_key = Crypto::PublicKey.new(secret: secret_key)
  users = TestUsers.new

  srv = TestServer.new(users, 12000 + crunch, secret_key)
  srv.disconnect_delay = 1000

  cli = TestClientEndpoint.new
  udp_cli = TestingClient.new(cli, Socket::IPAddress.new("127.0.0.1", 12000 + crunch))

  return {cli, udp_cli, srv, public_key, users}
end
