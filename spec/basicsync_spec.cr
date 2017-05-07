require "./spec_helper"

cli, udp_cli, srv, public_key, users = make_test_pair(0)
hash1 = users.demo_add_user("user1", "pass1")
hash2 = users.demo_add_user("user2", "pass2")
hash3 = users.demo_add_user("user3", "pass3")

it "test login" do
  udp_cli.login(public_key, "user1", hash1)
  answer = one_login(udp_cli)
  answer.should be_true
  SpecLogger.dump_events.should eq ["SERVER: adding connection", "SERVER: logged in: user1"]
end

srv_inst = srv.test_endpoint.not_nil!

it "basic data exchange" do
  cli.verbose = true
  srv_inst.verbose = true
  one_exchange(cli, udp_cli)
  SpecLogger.dump_events.should eq ["CLIENT: sending", "SERVER: received", "SERVER: sending", "CLIENT: received"]
end

it "can login again" do
  udp_cli.login(public_key, "user2", hash2)
  answer = one_login(udp_cli)
  answer.should be_true
  SpecLogger.dump_events.should eq ["SERVER: logged in: user2"]
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

it "debug_losses works on client" do
  cli.local_sync.data = "HELLO"
  cli.local_sync.num = 5
  udp_cli.debug_loss = true
  one_exchange(cli, udp_cli)
  srv.state.all_data[5].should_not eq "HELLO"
  one_exchange(cli, udp_cli)
  cli.remote_sync.all_data[5].should_not eq "HELLO"
  udp_cli.debug_loss = false
  one_exchange(cli, udp_cli)
  srv.state.all_data[5].should eq "HELLO"
  one_exchange(cli, udp_cli)
  cli.remote_sync.all_data[5].should eq "HELLO"
end

it "debug_losses works on server" do
  cli.local_sync.data = "OKAY"
  cli.local_sync.num = 5
  srv.debug_loss = true
  one_exchange(cli, udp_cli)
  srv.state.all_data[5].should eq "OKAY"
  one_exchange(cli, udp_cli)
  cli.remote_sync.all_data[5].should_not eq "OKAY"
  srv.debug_loss = false
  one_exchange(cli, udp_cli)
  cli.remote_sync.all_data[5].should eq "OKAY"
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

srv.disconnect_delay = 10
it "disconnects old clients" do
  # worsen latter reconnect
  SpecLogger.dump_events
  SpecLogger.dump_events.size.should eq 0
  srv.n_clients.should eq 1
  srv.skip_time(5)
  srv.n_clients.should eq 1
  srv.skip_time(6)
  srv.n_clients.should eq 0
  SpecLogger.dump_events.should eq ["SERVER: user disconnected: person2", "SERVER: connection complete"]
end

udp_cli.disconnect_timeout = 10

it "client relogins on timeout" do
  cli.verbose = true
  srv_inst.verbose = true
  one_login(udp_cli)
  one_exchange(cli, udp_cli)
  SpecLogger.dump_events.should eq ["SERVER: adding connection", "SERVER: logged in: user2", "CLIENT: sending", "CLIENT: received"]
end

it "works with client on another port" do
  acli = TestClientEndpoint.new
  audp_cli = MySync::UDPGameClient.new(acli, Socket::IPAddress.new("127.0.0.1", 12000 + 0))
  audp_cli.login(public_key, "user3", hash3)
  one_login(audp_cli)
  one_exchange(acli, audp_cli)
  SpecLogger.dump_events.should eq ["SERVER: adding connection", "SERVER: logged in: user3", "CLIENT: sending", "CLIENT: received"]
end

it "works with restarted client on same port" do
  srv.skip_time 1000
  SpecLogger.dump_events
  cli.verbose = true
  srv_inst.verbose = false
  acli = TestClientEndpoint.new
  # pretty hacky, but let it so
  acli.rpc_connection = MySync::CannonInterface.new(acli, udp_cli.rpc_manager)
  acli.sync_lists = MySync::SyncListsManager.new
  udp_cli.endpoint = acli
  udp_cli.login(public_key, "user2", hash2)
  answer = one_login(udp_cli)
  one_exchange(cli, udp_cli)
  SpecLogger.dump_events.should eq ["SERVER: adding connection", "SERVER: logged in: user2", "CLIENT: sending", "CLIENT: received"]
  srv.skip_time 1000
  SpecLogger.dump_events
end

it "rejects wrong login" do
  udp_cli.login(public_key, "testuser", hash1)
  answer = one_login(udp_cli)
  answer.should be_false
  udp_cli.auth_state.should eq MySync::AuthState::LoginFailed
  SpecLogger.dump_events.should eq ["SERVER: adding connection", "SERVER: failed to log in: testuser"]
  srv.skip_time 1000
  SpecLogger.dump_events
end

it "passwords actually hashed" do
  login = "slowuser"
  pass = "somepass"
  salt = Crypto::Salt.new
  hash = Crypto::SecretKey.new(password: pass, salt: salt)
  users.add_user(login, salt, hash)
  udp_cli.login(public_key, login, pass)
  answer = one_login(udp_cli)
  SpecLogger.dump_events.count("SERVER: logged in: slowuser").should be > 0
  answer.should be_true
  udp_cli.auth_state.should eq MySync::AuthState::LoggedIn
  udp_cli.save_hash.should eq hash
end

it "rejects wrong password" do
  users.registration_open = true
  udp_cli.login(public_key, "user1", hash2)
  p "1"
  answer = one_login(udp_cli)
  p "2"
  answer.should be_false
  udp_cli.auth_state.should eq MySync::AuthState::LoginFailed
  SpecLogger.dump_events.count("SERVER: logged in: user1").should be > 0
  one_exchange(cli, udp_cli)
  SpecLogger.dump_events.size.should eq 0
  srv.skip_time 1000
  SpecLogger.dump_events
  users.registration_open = false
end

pending "allows auto-registration" do
  users.registration_open = true
  login = "newuser"
  pass = "nopass"
  udp_cli.login(public_key, login, pass)
  answer = one_login(udp_cli)
  SpecLogger.dump_events.count("SERVER: logged in: newuser").should be > 0
  answer.should be_true
  udp_cli.auth_state.should eq MySync::AuthState::LoggedIn
  udp_cli.save_hash.should eq users.data[login][:hash]
  users.registration_open = false
  one_exchange(cli, udp_cli)
  SpecLogger.dump_events.should eq ["CLIENT: sending", "CLIENT: received"]
end

N1b = 100
N2b = 100
pending "process multiple connections" do
  srv.skip_time 1000
  SpecLogger.dump_events
  hashes = (0...N1b).map { |i| users.demo_add_user("benchuser#{i}", "pass") }
  srv.disconnect_delay = 5*60
  clients = [] of TestClientEndpoint
  N1b.times do |i|
    acli = TestClientEndpoint.new
    audp_cli = MySync::UDPGameClient.new(acli, Socket::IPAddress.new("127.0.0.1", 12000 + 0))
    do_login(audp_cli, users, public_key, "basicbench#{i}")
    acli.benchmark = N2b
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
  us = (t*1000000.0 / N1b / N1b).to_i
  p "time per packet: #{us} us"
end

# cleanup to prevent disconnect messages in next specs
srv.skip_time(1000)
SpecLogger.dump_events
