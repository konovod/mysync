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

cli, udp_cli, srv, udp_srv, public_key = make_test_pair
udp_cli.login(public_key, Bytes.new(1))
srv_inst = srv.test_endpoint.not_nil!

greeter = GreetClient.new cli.rpc_connection.not_nil!
udp_srv.rpc_manager.add GreetService.new

SpecLogger.dump_events

pending "direct sending of messages" do # need mocks?
  msg = Bytes.new(9) { |i| ('a'.ord + i).to_u8 }
  cli.cmd_buffer.add(msg)
  one_exchange(cli, udp_cli)
  p SpecLogger.dump_events
end

it "rpc without response" do
  SpecLogger.dump_events
  greeter.no_answer_without_response "test"
  one_exchange(cli, udp_cli)
  SpecLogger.dump_events.should eq ["CLIENT: sending", "SERVER: no_answer test", "CLIENT: received"]
end

pending "rpc without response with loses" do
  greeter.no_answer_without_response "test"
  udp_cli.debug_loses = true
  10.times do
    one_exchange(cli, udp_cli)
  end
  greeter.no_answer_without_response "test2"
  udp_cli.debug_loses = false
  10.times do
    one_exchange(cli, udp_cli)
  end
  p SpecLogger.dump_events
  # SpecLogger.dump_events.count("SERVER: no_answer test").should eq 1
  # SpecLogger.dump_events.count("SERVER: no_answer test2").should eq 1
end

pending "rpc with response" do
  spawn do
    pp greeter.greet("Alice")
    start = Time.now
    pong = greeter.ping Time.now
    finish = Time.now
    puts "      Ping time: #{pong - start}"
    puts "Round-trip time: #{finish - start}"
  end

  udp_cli.debug_loses = true
  10.times do
    one_exchange(cli, udp_cli)
  end
  udp_cli.debug_loses = false
  10.times do
    one_exchange(cli, udp_cli)
  end
end
