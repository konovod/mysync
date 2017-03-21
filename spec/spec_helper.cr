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

# compiler bug?
# TODO - identify minimal example
######################
macro solve_bug

  def process_receive(data)
    super
  end

  def process_sending
    super
  end

  def local_seq=(value)
    super
  end

  def remote_seq=(value)
    super
  end

  def local_seq
    super
  end

  def remote_seq
    super
  end

end

class TestUserContext < MySync::EndPoint(TestServerOutput, TestClientInput)
  property verbose : Bool = false

  def on_disconnect
    SpecLogger.log_srv "user disconnected: #{@user}"
  end

  def on_received_sync
    SpecLogger.log_srv "received" if @verbose
    @server.state.all_data[@remote_sync.num] = @remote_sync.data if @remote_sync.num >= 0
  end

  def before_sending_sync
    SpecLogger.log_srv "sending" if @verbose
    @local_sync = @server.state
  end

  solve_bug

  def initialize(@server : TestServer, @user : Int32)
    super()
  end
end

class TestServer
  include MySync::EndPointFactory
  property state = TestServerOutput.new
  getter test_endpoint : MySync::AbstractEndPoint?

  def new_endpoint(authdata : Bytes) : {endpoint: MySync::AbstractEndPoint, response: Bytes}?
    username = String.new(authdata)
    SpecLogger.log_srv "logged in: #{username}"
    userid = 2
    point = TestUserContext.new(self, userid)
    @test_endpoint = point
    {endpoint: point, response: "you_can_pass".to_slice}
  end

  def on_connecting(ip : Socket::IPAddress)
    p "adding connection #{ip}"
    SpecLogger.log_srv "adding connection"
  end

  def on_disconnecting(ip : Socket::IPAddress, ex : Exception?)
    if ex
      p "connection #{ip} raised #{ex}"
      SpecLogger.log_srv "connection raised #{ex}"
    else
      p "connection #{ip} complete"
      SpecLogger.log_srv "connection complete"
    end
  end
end

class TestClientEndpoint < MySync::EndPoint(TestClientInput, TestServerOutput)
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

  solve_bug
end

def one_exchange(cli, udp_cli)
  ans = Channel(Nil).new
  spawn do
    sleep 0.1.seconds
    ans.send nil
  end
  cli.wait_answer = ans
  udp_cli.send_manually
  ans.receive
  cli.wait_answer = nil
end

def make_test_pair
  secret_key = Crypto::SecretKey.new
  public_key = Crypto::PublicKey.new(secret: secret_key)

  srv = TestServer.new
  udp_srv = MySync::UDPGameServer.new(srv, 12000, secret_key)
  udp_srv.disconnect_delay = 1.minutes

  cli = TestClientEndpoint.new
  udp_cli = MySync::UDPGameClient.new(cli, Socket::IPAddress.new("127.0.0.1", 12000))
  udp_cli.login(public_key, Bytes.new(0))

  return {cli, udp_cli, srv, udp_srv, public_key}
end
