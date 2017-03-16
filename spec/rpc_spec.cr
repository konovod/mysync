require "./spec_helper"

module GreetDescription
  include Cannon::Rpc::SingletonService(1)

  abstract def greet(text : String, conn : Cannon::Rpc::Connection) : String
  abstract def ping(client_time : Time) : Time
end

class GreetService
  include Cannon::Rpc::Service(GreetDescription)

  def greet(text : String, conn : Cannon::Rpc::Connection) : String
    # TODO - conn to clientdata
    SpecLogger.log_srv "greeting #{text}"
    "hello #{text}"
  end

  def ping(client_time : Time) : Time
    my_time = Time.now
    SpecLogger.log_srv "Client ping: #{my_time - client_time}"
    my_time
  end
end

# service_manager = Cannon::Rpc::Manager.new
# service_manager.add GreetService.new
#
# it "do async commands" do
# end
def spec_rpc(cli, srv)
  it "works" do
    false.should eq true
  end
end
