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
def spec_rpc(cli, srv_inst, udp_cli, udp_srv)
  greeter = GreetClient.new cli.rpc_connection.not_nil!
  udp_srv.rpc_manager.add GreetService.new

  SpecLogger.dump_events

  pending "direct sending of messages" do # temporary
    msg = Bytes.new(9) { |i| ('a'.ord + i).to_u8 }
    cli.cmd_buffer.add(msg)
    # udp_cli.send_data
    # sleep 0.1
    # p SpecLogger.dump_events
  end

  # greeter.ping(Time.now)
  greeter.no_answer_without_response "test"
  udp_cli.send_data
  sleep 0.1
  p SpecLogger.dump_events

  spawn do
    pp greeter.greet("Alice")
    start = Time.now
    pong = greeter.ping Time.now
    finish = Time.now
    puts "      Ping time: #{pong - start}"
    puts "Round-trip time: #{finish - start}"
  end

  5.times do
    udp_cli.send_data
    sleep 0.1
  end
  p SpecLogger.dump_events
end
