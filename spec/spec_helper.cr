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

  def on_received_sync
    SpecLogger.log_srv "received" if @verbose
    @server.state.all_data[@remote_sync.num] = @remote_sync.data if @remote_sync.num >= 0
  end

  def before_sending_sync
    SpecLogger.log_srv "sending" if @verbose
    @local_sync = @server.state
  end

  def initialize(@server : TestServer, @user : Int32, @username : String)
    super()
  end
end

class TestServer
  include MySync::EndPointFactory
  property state = TestServerOutput.new
  getter test_endpoint : MySync::EndPoint?

  def new_endpoint(authdata : Bytes) : {endpoint: MySync::EndPoint?, response: Bytes}?
    username = String.new(authdata)
    if username == "INVALID"
      SpecLogger.log_srv "failed to log in: #{username}"
      {endpoint: nil, response: "you_won't_pass".to_slice}
    else
      SpecLogger.log_srv "logged in: #{username}"
      userid = 2
      point = TestUserContext.new(self, userid, username)
      @test_endpoint = point
      {endpoint: point, response: "you_can_pass".to_slice}
    end
  end

  def on_connecting(ip : Socket::IPAddress)
    # p "adding connection #{ip}"
    SpecLogger.log_srv "adding connection"
  end

  def on_disconnecting(ip : Socket::IPAddress, ex : Exception?)
    if ex
      p "connection #{ip} raised #{ex}"
      SpecLogger.log_srv "connection raised"
    else
      # p "connection #{ip} complete"
      SpecLogger.log_srv "connection complete"
    end
  end
end

class TestClientEndpoint < MySync::EndPoint
  set_local_sync TestClientInput
  set_remote_sync TestServerOutput

  property benchmark : Int32 = 0
  property benchmark_udp : MySync::UDPGameClient?
  getter benchmark_complete = Channel(Nil).new
  property wait_answer : Channel(Nil)?
  property verbose : Bool = true

  def on_received_sync
    SpecLogger.log_cli "received" if @verbose
    if @benchmark > 0
      @benchmark -= 1
      if @benchmark == 0
        @benchmark_complete.send(nil)
      else
        @benchmark_udp.not_nil!.send_manually
      end
    elsif w = @wait_answer
      w.send(nil)
    end
  end

  def before_sending_sync
    SpecLogger.log_cli "sending" if @verbose
  end
end

def one_exchange(cli, udp_cli)
  ans = Channel(Nil).new
  spawn do
    sleep 0.05.seconds
    ans.send nil
  end
  cli.wait_answer = ans
  udp_cli.send_manually
  ans.receive
  cli.wait_answer = nil
end

def one_login(udp_cli)
  udp_cli.autosend_delay = 0.1.seconds
  answer = udp_cli.wait_login
  udp_cli.autosend_delay = nil
  return answer
end

class TestingClient < MySync::UDPGameClient
  def endpoint=(point)
    @endpoint = point
  end
end

def make_test_pair(crunch)
  secret_key = Crypto::SecretKey.new
  public_key = Crypto::PublicKey.new(secret: secret_key)

  srv = TestServer.new
  udp_srv = MySync::UDPGameServer.new(srv, 12000 + crunch, secret_key)
  udp_srv.disconnect_delay = 1.minutes

  cli = TestClientEndpoint.new
  udp_cli = TestingClient.new(cli, Socket::IPAddress.new("127.0.0.1", 12000 + crunch))
  udp_cli.login(public_key, Bytes.new(0))

  return {cli, udp_cli, srv, udp_srv, public_key}
end
