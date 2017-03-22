require "./spec_helper"

cli, udp_cli, srv, udp_srv, public_key = make_test_pair

it "test login" do
  udp_cli.login(public_key, "it_s_me".to_slice)
  udp_cli.autosend_delay = 0.1.seconds
  # udp_cli.send_manually
  answer = udp_cli.wait_login
  udp_cli.autosend_delay = nil
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
  udp_cli.autosend_delay = 0.1.seconds
  # udp_cli.send_manually
  answer = udp_cli.wait_login
  udp_cli.autosend_delay = nil
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

it "gather stats for packets" do
  cli.verbose = false
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
  SpecLogger.dump_events
  SpecLogger.dump_events.size.should eq 0
  udp_srv.n_clients.should eq 1
  udp_srv.disconnect_delay = 0.01.seconds
  sleep(0.5.seconds)
  udp_srv.n_clients.should eq 0
  SpecLogger.dump_events.should eq ["SERVER: user disconnected: 2", "SERVER: connection complete"]
end

udp_cli.disconnect_timeout = 0.2.seconds

it "client relogins on timeout" do
  udp_cli.autosend_delay = 0.1.seconds
  # udp_cli.send_manually
  answer = udp_cli.wait_login
  udp_cli.autosend_delay = nil
  SpecLogger.dump_events.should eq ["SERVER: adding connection", "SERVER: logged in: it_s_another"]
end