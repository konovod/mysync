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


def log_srv(s : String)
  puts "SERVER: #{s}"
end

def log_cli(s : String)
  puts "CLIENT: #{s}"
end

class TestUserContext < MySync::UserContext(TestClientInput, TestServerOutput)

  def on_disconnect
    log_srv "user disconnected: #{@user}"
  end
  def on_received_sync
    log_srv "received: #{@remote_sync}"
    #@server.state.all_data[@remote_sync.num] = @remote_sync.str if @remote_sync.num >= 0
  end
  def before_sending_sync
    @local_sync = @server.state
    log_srv "sending: #{@local_sync}"
  end

  def initialize(aserver, auser)
    super(aserver, auser)
  end

end

class TestServer < MySync::Server(TestClientInput, TestServerOutput)
  property state = TestServerOutput.new

  def on_login(user)
    log_srv "logged in: #{user}"
    return TestUserContext.new(self, user)
  end

  def on_register(user)
    log_srv "registered: #{user}"
    return TestUserContext.new(self, user)
  end

end


class TestClient < MySync::Client(TestClientInput, TestServerOutput)

  def on_connected(user : MySync::UserID)
    log_cli "logged in: #{user}"
  end

  def on_received_sync
    log_cli "received"
  end

  def before_sending_sync

  end


end



describe "basic client\server" do
  srv = TestServer.new
  cli = TestClient.new
  srv_inst = srv.on_login(2)
  cli.on_connected(2)

  it "works" do

  end

  it "parse packets when passed directly" do
    n = cli.process_sending
    srv_inst.package_received.copy_from(cli.package_tosend.to_unsafe, n)
    srv_inst.process_receive
  end


end
