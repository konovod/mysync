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

cli, udp_cli, srv, udp_srv, public_key = make_test_pair(1)
udp_cli.login(public_key, Bytes.new(1))
one_login(udp_cli)
srv_inst = srv.test_endpoint.not_nil!

greeter = GreetClient.new cli.rpc_connection.not_nil!
srv.rpc_manager.add GreetService.new

SpecLogger.dump_events

pending "direct sending of messages" do # need mocks?
  msg = Bytes.new(9) { |i| ('a'.ord + i).to_u8 }
  cli.cmd_buffer.add(msg)
  one_exchange(cli, udp_cli)
  p SpecLogger.dump_events
end

cli.verbose = false
it "rpc without response" do
  SpecLogger.dump_events
  greeter.no_answer_without_response "test"
  one_exchange(cli, udp_cli)
  SpecLogger.dump_events.should eq ["SERVER: no_answer test"]
end

it "rpc several commands at same time" do
  SpecLogger.dump_events
  greeter.no_answer_without_response "test1"
  greeter.no_answer_without_response "test2"
  one_exchange(cli, udp_cli)
  SpecLogger.dump_events.should eq ["SERVER: no_answer test1", "SERVER: no_answer test2"]
end

it "rpc several commands at same time #2" do
  SpecLogger.dump_events
  5.times { greeter.no_answer_without_response "test" }
  one_exchange(cli, udp_cli)
  SpecLogger.dump_events.count("SERVER: no_answer test").should eq 5
  one_exchange(cli, udp_cli)
  SpecLogger.dump_events.count("SERVER: no_answer test").should eq 0
end

it "don't repeat old procedures" do
  SpecLogger.dump_events
  udp_cli.debug_loss = true
  20.times do
    # one_exchange(cli, udp_cli)
    udp_cli.send_manually
  end
  udp_cli.debug_loss = false
  10.times do
    udp_cli.send_manually
    # one_exchange(cli, udp_cli)
  end
  sleep 0.2
  10.times do
    one_exchange(cli, udp_cli)
  end
  SpecLogger.dump_events.count("SERVER: no_answer test").should eq 0
end

it "resend delay works" do
  SpecLogger.dump_events
  greeter.no_answer_without_response "missing"
  udp_cli.debug_loss = true
  one_exchange(cli, udp_cli)
  SpecLogger.dump_events.count("SERVER: no_answer missing").should eq 0
  udp_cli.debug_loss = false
  one_exchange(cli, udp_cli)
  SpecLogger.dump_events.count("SERVER: no_answer missing").should eq 0
  sleep 0.25
  one_exchange(cli, udp_cli)
  SpecLogger.dump_events.count("SERVER: no_answer missing").should eq 1
end

it "rpc without response with loses" do
  SpecLogger.dump_events
  greeter.no_answer_without_response "test1"
  udp_cli.debug_loss = true
  5.times do
    one_exchange(cli, udp_cli)
  end
  sleep 0.2
  greeter.no_answer_without_response "test2"
  udp_cli.debug_loss = false
  20.times do
    one_exchange(cli, udp_cli)
  end
  SpecLogger.dump_events.should eq ["SERVER: no_answer test1", "SERVER: no_answer test2"]
end

it "rpc without response with loses #2" do
  SpecLogger.dump_events
  greeter.no_answer_without_response "test1"
  udp_srv.debug_loss = true
  5.times do
    one_exchange(cli, udp_cli)
  end
  sleep 0.2
  greeter.no_answer_without_response "test2"
  udp_srv.debug_loss = false
  20.times do
    one_exchange(cli, udp_cli)
  end
  SpecLogger.dump_events.should eq ["SERVER: no_answer test1", "SERVER: no_answer test2"]
end

it "rpc with response" do
  done = Channel(Nil).new
  udp_cli.debug_loss = true
  udp_srv.debug_loss = true
  udp_cli.autosend_delay = 0.05.seconds
  udp_cli.autologin_delay = 0.05.seconds
  spawn do
    greeter.greet("Alice").should eq "hello Alice"
    start = Time.now
    pong = greeter.ping Time.now
    finish = Time.now
    p "Response: #{finish - pong}"
    done.send nil
  end
  sleep 0.2
  udp_cli.debug_loss = false
  sleep 0.2
  udp_srv.debug_loss = false
  done.receive
end

udp_cli.autosend_delay = nil
sleep 0.2

it "shrink large stream to single commands" do
  SpecLogger.dump_events
  2.times { greeter.no_answer_without_response "0123456789" }
  one_exchange(cli, udp_cli)
  SpecLogger.dump_events.count("SERVER: no_answer 0123456789").should eq 2
  100.times { greeter.no_answer_without_response "0123456789" }
  one_exchange(cli, udp_cli)
  SpecLogger.dump_events.count("SERVER: no_answer 0123456789").should eq 1
  5.times { one_exchange(cli, udp_cli) }
  SpecLogger.dump_events.count("SERVER: no_answer 0123456789").should eq 5
  100.times { one_exchange(cli, udp_cli) }
  SpecLogger.dump_events.count("SERVER: no_answer 0123456789").should eq 100 - 1 - 5
end

# how to expect raising in another fiber
pending "raises when message is too long" do
  # expect_raises(Exception) do
  SpecLogger.dump_events
  greeter.greet_without_response(String.new(Bytes.new(10000)))
  one_exchange(cli, udp_cli)
  p SpecLogger.dump_events
  # end
end
