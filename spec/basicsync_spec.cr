require "./spec_helper"

cli, udp_cli, srv, udp_srv, public_key = make_test_pair(0)

it "test login" do
  udp_cli.login(public_key, "it_s_me".to_slice)
  answer = one_login(udp_cli)
  String.new(answer.not_nil!).should eq "you_can_pass"
  SpecLogger.dump_events.should eq ["SERVER: adding connection", "SERVER: logged in: it_s_me"]
end

srv_inst = srv.test_endpoint.not_nil!

it "basic data exchange" do
  cli.verbose = true
  srv_inst.verbose = true
  one_exchange(cli, udp_cli)
  SpecLogger.dump_events.should eq ["CLIENT: sending", "SERVER: received", "SERVER: sending", "CLIENT: received"]
end

it "can login again" do
  udp_cli.login(public_key, "it_s_another".to_slice)
  answer = one_login(udp_cli)
  String.new(answer.not_nil!).should eq "you_can_pass"
  SpecLogger.dump_events.should eq ["SERVER: logged in: it_s_another"]
end
srv_inst = srv.test_endpoint.not_nil!

it "passed data are applied" do
  cli.local_sync.data = "hello"
  cli.local_sync.num = 5

  one_exchange(cli, udp_cli)
  srv.state.all_data[5].should eq "hello"
  one_exchange(cli, udp_cli)
  cli.remote_sync.all_data[5].should eq "hello"
end

# TODO - specs for ack_mask
it "update seq_iq" do
  cli.local_seq = 5u16
  cli.remote_seq = 15u16
  srv_inst.local_seq = 18u16
  srv_inst.remote_seq = 7u16

  one_exchange(cli, udp_cli)

  cli.local_seq.should eq 6u16
  srv_inst.remote_seq.should eq 7u16

  one_exchange(cli, udp_cli)

  srv_inst.local_seq.should eq 20u16
  cli.remote_seq.should eq 20u16
end

it "process faraway packets" do
  cli.verbose = true
  srv_inst.verbose = true
  SpecLogger.dump_events
  cli.local_seq = 509u16
  cli.remote_seq = 515u16
  srv_inst.local_seq = 518u16
  srv_inst.remote_seq = 507u16
  one_exchange(cli, udp_cli)
  SpecLogger.dump_events.should eq ["CLIENT: sending", "SERVER: received", "SERVER: sending", "CLIENT: received"]
end

it "gather stats for packets" do
  cli.verbose = false
  srv_inst.verbose = false
  cur = Time.now
  cli.benchmark = 1000
  cli.benchmark_udp = udp_cli
  udp_cli.send_manually
  cli.benchmark_complete.receive
  pp (Time.now - cur).to_f # *1000 / 1000
  pp cli.stat_losses
  pp cli.stat_pingtime*1000
end

it "disconnects old clients" do
  # worsen latter reconnect
  SpecLogger.dump_events
  SpecLogger.dump_events.size.should eq 0
  udp_srv.n_clients.should eq 1
  udp_srv.disconnect_delay = 0.01.seconds
  sleep(0.5.seconds)
  udp_srv.n_clients.should eq 0
  SpecLogger.dump_events.should eq ["SERVER: user disconnected: it_s_another", "SERVER: connection complete"]
  udp_srv.disconnect_delay = 0.1.seconds
end

udp_cli.disconnect_timeout = 0.2.seconds

it "client relogins on timeout" do
  cli.verbose = true
  srv_inst.verbose = true
  one_login(udp_cli)
  one_exchange(cli, udp_cli)
  SpecLogger.dump_events.should eq ["SERVER: adding connection", "SERVER: logged in: it_s_another", "CLIENT: sending", "CLIENT: received"]
end

it "works with client on another port" do
  acli = TestClientEndpoint.new
  audp_cli = MySync::UDPGameClient.new(acli, Socket::IPAddress.new("127.0.0.1", 12000 + 0))
  audp_cli.login(public_key, Bytes.new(0))
  one_login(audp_cli)
  one_exchange(acli, audp_cli)
  SpecLogger.dump_events.should eq ["SERVER: adding connection", "SERVER: logged in: ", "CLIENT: sending", "CLIENT: received"]
end

it "works with restarted client on same port" do
  sleep(0.5.seconds)
  SpecLogger.dump_events
  cli.verbose = true
  srv_inst.verbose = false
  acli = TestClientEndpoint.new
  udp_cli.endpoint = acli
  udp_cli.login(public_key, "it_s_another2".to_slice)
  answer = one_login(udp_cli)
  one_exchange(cli, udp_cli)
  SpecLogger.dump_events.should eq ["SERVER: adding connection", "SERVER: logged in: it_s_another2", "CLIENT: sending", "CLIENT: received"]
end

N = 100
it "process multiple connections" do
  udp_srv.disconnect_delay = 1.seconds
  clients = [] of TestClientEndpoint
  N.times do
    acli = TestClientEndpoint.new
    audp_cli = MySync::UDPGameClient.new(acli, Socket::IPAddress.new("127.0.0.1", 12000 + 0))
    audp_cli.login(public_key, Bytes.new(0))
    one_login(audp_cli)
    # audp_cli.autosend_delay = 0.05.seconds
    acli.benchmark = 1000
    acli.benchmark_udp = audp_cli
    clients << acli
  end
  clients.each do |acli|
    acli.benchmark_udp.not_nil!.send_manually
  end
  clients.each do |acli|
    acli.benchmark_complete.receive
  end
  t = clients.sum &.stat_pingtime
  pp t*1000.0 / N
end
