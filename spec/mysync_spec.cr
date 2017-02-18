require "./spec_helper"
require "cannon"

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
  def initialize()
   @all_data = StaticArray(String, 16).new("")
  end
  def initialize(@all_data)
  end

end

class TestUserContext < MySync::UserContext(TestClientInput, TestServerOutput)

  def on_disconnect
    SpecLogger.log_srv "user disconnected: #{@user}"
  end
  def on_received_sync
    @server.state.all_data[@remote_sync.num] = @remote_sync.data if @remote_sync.num >= 0
  end
  def before_sending_sync
    @local_sync = @server.state
  end

  def initialize(aserver, auser)
    super(aserver, auser)
  end

end

class TestServer < MySync::Server(TestClientInput, TestServerOutput)
  property state = TestServerOutput.new

  def on_login(user)
    SpecLogger.log_srv "logged in: #{user}"
    return TestUserContext.new(self, user)
  end

  def on_register(user, data)
    SpecLogger.log_srv "registered: #{user}"
    return TestUserContext.new(self, user)
  end

end


class TestClient < MySync::Client(TestClientInput, TestServerOutput)

  getter! user : MySync::UserID

  def on_connected(user : MySync::UserID)
    SpecLogger.log_cli "logged in: #{user}"
    @user = user
  end

  def on_received_sync
    SpecLogger.log_cli "received"
  end

  def before_sending_sync

  end


end

def direct_xchange(sender, receiver)
  n = sender.process_sending
  receiver.package_received.copy_from(sender.package_tosend.to_unsafe, n)
  receiver.process_receive
end

def server_xchange(client, server)
  n_cli = client.process_sending
  n_ser = server.packet_received(client.user, Bytes.new(client.package_tosend.to_unsafe, n_cli), client.package_received)
  client.process_receive if n_ser > 0
end


describe "basic client/server" do
  srv = TestServer.new
  cli = TestClient.new
  srv_inst = srv.do_login(2).not_nil!
  cli.on_connected(2)

  it "works" do
    SpecLogger.dump_events.should eq ["SERVER: logged in: 2", "CLIENT: logged in: 2"]
  end

  it "parse packets when passed directly" do
    cli.local_sync.data = "hello"
    cli.local_sync.num = 5

    direct_xchange(cli, srv_inst)
    direct_xchange(srv_inst, cli)
    srv.state.all_data[5].should eq "hello"
    cli.remote_sync.all_data[5].should eq "hello"
  end

  it "parse packets when passed through server interface" do
    cli.local_sync.data = "hello2"
    cli.local_sync.num = 6

    server_xchange(cli, srv)
    srv.state.all_data[6].should eq "hello2"
    cli.remote_sync.all_data[6].should eq "hello2"
  end


  it "update seq_iq" do
    cli.local_seq = 5u16
    cli.remote_seq = 15u16
    srv_inst.local_seq = 18u16
    srv_inst.remote_seq = 7u16
    direct_xchange(cli, srv_inst)
    cli.local_seq.should eq 6u16
    srv_inst.remote_seq.should eq 7u16
    direct_xchange(srv_inst, cli)
    srv_inst.local_seq.should eq 19u16
    cli.remote_seq.should eq 19u16
  end

  it "disconnects old clients" do
    SpecLogger.dump_events
    srv.dump_oldies
    SpecLogger.dump_events.size.should eq 0
    sleep(1.5)
    srv.dump_oldies
    SpecLogger.dump_events.should eq ["SERVER: user disconnected: 2"]
  end


end
