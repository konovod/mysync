require "./spec_helper"

class TestUserContext < MySync::EndPoint(TestServerOutput, TestClientInput)
  def on_disconnect
    SpecLogger.log_srv "user disconnected: #{@user}"
  end

  def on_received_sync
    @server.state.all_data[@remote_sync.num] = @remote_sync.data if @remote_sync.num >= 0
  end

  def before_sending_sync
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
end

class TestClientEndpoint < MySync::EndPoint(TestClientInput, TestServerOutput)
  property benchmark : Int32 = 0
  property benchmark_udp : MySync::UDPGameClient?
  getter benchmark_chan = Channel(Nil).new

  def on_received_sync
    if @benchmark > 0
      @benchmark -= 1
      if @benchmark == 0
        @benchmark_chan.send(nil)
      else
        @benchmark_udp.not_nil!.send_data
      end
    else
      SpecLogger.log_cli "received"
    end
  end

  def before_sending_sync
    SpecLogger.log_cli "sending"
  end

  solve_bug
end

secret_key = Crypto::SecretKey.new("c4b12631c3f68e7a72fc760a31ffaae0a7a5f8d892cac43c0d8d06acd1b3fd8f")
public_key = Crypto::PublicKey.new(secret: secret_key)

srv = TestServer.new
udp_srv = MySync::UDPGameServer.new(srv, 12000, secret_key)

cli = TestClientEndpoint.new
udp_cli = MySync::UDPGameClient.new(cli, Socket::IPAddress.new("127.0.0.1", 12000))

it "test login" do
  answer = udp_cli.login(public_key, "it_s_me".to_slice)
  String.new(answer.not_nil!).should eq "you_can_pass"
  SpecLogger.dump_events.should eq ["SERVER: logged in: it_s_me"]
end

it "basic data exchange" do
  udp_cli.send_data
  sleep 0.1
  SpecLogger.dump_events.should eq ["CLIENT: sending", "CLIENT: received"]
end

it "passed data are applied" do
  cli.local_sync.data = "hello"
  cli.local_sync.num = 5

  udp_cli.send_data
  sleep 0.1

  srv.state.all_data[5].should eq "hello"
  cli.remote_sync.all_data[5].should eq "hello"
end

srv_inst = srv.test_endpoint.not_nil!
it "update seq_iq" do
  cli.local_seq = 5u16
  cli.remote_seq = 15u16
  srv_inst.local_seq = 18u16
  srv_inst.remote_seq = 7u16

  udp_cli.send_data
  sleep 0.1

  cli.local_seq.should eq 6u16
  srv_inst.remote_seq.should eq 7u16

  udp_cli.send_data
  sleep 0.1

  srv_inst.local_seq.should eq 20u16
  cli.remote_seq.should eq 20u16
end

it "gather stats for packets" do
  cur = Time.now
  cli.benchmark = 1000
  cli.benchmark_udp = udp_cli
  udp_cli.send_data
  cli.benchmark_chan.receive
  pp (Time.now - cur).to_f # *1000 / 1000
  pp cli.stat_losses
  pp cli.stat_pingtime*1000
end

it "disconnects old clients" do
  SpecLogger.dump_events
  SpecLogger.dump_events.size.should eq 0
  udp_srv.n_clients.should eq 1
  sleep(1.5)
  udp_srv.n_clients.should eq 0
  SpecLogger.dump_events.should eq ["SERVER: user disconnected: 2"]
end

#
# end
