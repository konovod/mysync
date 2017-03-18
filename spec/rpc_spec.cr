require "./spec_helper"

module GreetDescription
  include Cannon::Rpc::SingletonService(1)

  abstract def greet(text : String, conn : Cannon::Rpc::Connection) : String
  abstract def ping(client_time : Time) : Time
  abstract def no_answer(text : String) : Nil
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

  def no_answer(text : String) : Nil
    SpecLogger.log_srv "no_answer #{text}"
  end
end

class GreetClient
  include Cannon::Rpc::RemoteService(GreetDescription)
end

# service_manager = Cannon::Rpc::Manager.new
# service_manager.add GreetService.new
#
# it "do async commands" do
# end
def spec_rpc(cli, srv)
  greeter = GreetClient.new cli.rpc_connection
  srv.rpc_manager.add GreetService.new

  SpecLogger.dump_events
  # greeter.ping(Time.now)
  greeter.no_answer_without_response "test"
  cli.send_data
  sleep 0.1
  p SpecLogger.dump_events
end
