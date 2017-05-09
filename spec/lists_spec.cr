require "./spec_helper"
require "../src/mysync/payloads/lists"
require "../src/mysync/utils/uniqid"

# on client side - client contains lists manager, inside there are lists.
# There are commands to make, remove and update items

class Player < MySync::ListItem
  property name
  property hp

  def initialize(@id, @name = "", @hp = 100)
  end
end

record PlayerAdder, name : String, hp : Int32 do
  include Cannon::Auto
end
record PlayerUpdater, hp : Int32 do
  include Cannon::Auto
end

class ClientPlayersList < MySync::ClientSyncList
  include MySync::SyncListData(Player, PlayerAdder, PlayerUpdater)
  getter players = [] of Player

  def item_added(id, data)
    Player.new(id).tap do |player|
      players << player
      player.name = data.name
      player.hp = data.hp
    end
  end

  def item_removed(player)
    players.delete player
  end

  def item_updated(player, data)
    player.hp = data.hp
  end
end

class ServerPlayersList < MySync::ServerSyncList
  include MySync::ServerSyncListImplementation(Player, PlayerAdder, PlayerUpdater)
  getter all_players = [] of Player
  @uids = MySync::IDS.new

  def full_state(item)
    PlayerAdder.new(item.name, item.hp)
  end

  def delta_state(item)
    PlayerUpdater.new(item.hp)
  end

  def iterate(who, &block)
    @all_players.each { |pl| yield(pl) }
  end

  def new_player(name, hp)
    Player.new(@uids.generate, name, hp).tap do |pl|
      all_players << pl
    end
  end

  def delete_player(player)
    all_players.delete player
    @uids.recycle player.id
  end
end

class Bullet < MySync::ListItem
  property typ = 0
  property x = 0
  property y = 0
end

@[Packed]
record BulletAdder, typ : UInt8, x : Int16, y : Int16 do
  include Cannon::Auto
end

class ClientBulletsList < MySync::ClientSyncList
  include MySync::SyncListData(Bullet, BulletAdder, Nil)
  getter bullets = [] of Bullet

  def item_added(id, data)
    Bullet.new(id).tap do |bullet|
      bullets << bullet
      bullet.typ = data.typ.to_i
      bullet.x = data.x.to_i
      bullet.y = data.y.to_i
    end
  end

  def item_removed(bullet)
    bullets.delete bullet
  end

  def item_updated(bullet, data)
  end
end

class ServerBulletsList < MySync::ServerSyncList
  include MySync::ServerSyncListImplementation(Bullet, BulletAdder, Nil)
  getter all_bullets = [] of Bullet
  @uids = MySync::IDS.new

  def full_state(item)
    BulletAdder.new(UInt8.new(item.typ), Int16.new(item.x), Int16.new(item.y))
  end

  def delta_state(item)
    nil
  end

  def iterate(who, &block)
    @all_bullets.each { |pl| yield(pl) }
  end

  def new_bullet(n)
    Bullet.new(@uids.generate).tap do |pl|
      pl.typ = n
      pl.x = n
      pl.y = n
      all_bullets << pl
    end
  end

  def delete_bullet(bullet)
    all_bullets.delete bullet
    @uids.recycle bullet.id
  end
end

cli, udp_cli, srv, public_key, users = make_test_pair(3)

cli_list = ClientPlayersList.new(cli.time)
srv_list = ServerPlayersList.new
cli_list2 = ClientBulletsList.new(cli.time)
srv_list2 = ServerBulletsList.new

cli.sync_lists << cli_list
srv.sync_lists << srv_list
cli.sync_lists << cli_list2
srv.sync_lists << srv_list2

do_login(udp_cli, srv, users, public_key, "lists")
srv_inst = srv.test_endpoint.not_nil!

it "starts empty" do
  cli_list.players.size.should eq 0
  srv_list.all_players.size.should eq 0
end

it "syncs added elements" do
  srv_list.new_player("test", 99)
  one_exchange(cli, udp_cli, srv)
  cli_list.players.size.should eq 1
  cli_list.players[0].name.should eq "test"
  cli_list.players[0].hp.should eq 99
  srv_list.new_player("test2", 98)
  one_exchange(cli, udp_cli, srv)
  cli_list.players.size.should eq 2
  cli_list.players[1].name.should eq "test2"
  cli_list.players[1].hp.should eq 98
end

it "syncs deleting elements" do
  srv_list.delete_player(srv_list.all_players[0])
  one_exchange(cli, udp_cli, srv)
  cli_list.players.size.should eq 1
  cli_list.players[0].name.should eq "test2"
end

it "syncs updating elements" do
  pl1 = srv_list.all_players[0]
  pl1.hp = 50
  cli_list.players[0].hp.should_not eq 50
  one_exchange(cli, udp_cli, srv)
  cli_list.players[0].hp.should eq 50
end

it "use delta for updating elements" do
  pl1 = srv_list.all_players[0]
  old = pl1.name
  pl1.name = "me"
  cli_list.players[0].name.should_not eq "me"
  one_exchange(cli, udp_cli, srv)
  cli_list.players[0].name.should_not eq "me"
  cli_list.players[0].name = old
  pl1.name = old
end

it "syncs adding in case of packets loss" do
  old = srv_list.all_players[0].name
  srv_list.new_player("test3", 99)
  srv.debug_loss = true
  one_exchange(cli, udp_cli, srv)
  one_exchange(cli, udp_cli, srv)
  udp_cli.debug_loss = true
  srv_list.new_player("test4", 99)
  one_exchange(cli, udp_cli, srv)
  one_exchange(cli, udp_cli, srv)
  cli_list.players.size.should eq 1
  srv.debug_loss = false
  udp_cli.debug_loss = false
  one_exchange(cli, udp_cli, srv)
  cli_list.players.size.should eq 3
  one_exchange(cli, udp_cli, srv)
  cli_list.players.map(&.name).sort.should eq ["test3", "test4", old].sort
end

it "syncs deleting in case of packets loss" do
  name = srv_list.all_players[0].name
  srv_list.delete_player(srv_list.all_players[0])
  cli_list.players[0].name.should eq name
  srv.debug_loss = true
  one_exchange(cli, udp_cli, srv)
  one_exchange(cli, udp_cli, srv)
  cli_list.players[0].name.should eq name
  srv.debug_loss = false
  one_exchange(cli, udp_cli, srv)
  cli_list.players[0].name.should eq name
  cli_list.fading_delay = 1
  sleep 0.1
  one_exchange(cli, udp_cli, srv)
  cli_list.players[0].name.should_not eq name
  cli_list.fading_delay = 60
end

it "syncing a second list" do
  srv_list2.new_bullet(99)
  one_exchange(cli, udp_cli, srv)
  cli_list2.bullets.size.should eq 1
  cli_list2.bullets[0].typ.should eq 99
  cli_list2.bullets[0].x.should eq 99
  srv_list2.new_bullet(98)
  one_exchange(cli, udp_cli, srv)
  cli_list2.bullets.size.should eq 2
  cli_list2.bullets[0].typ.should eq 99
  cli_list2.bullets[1].typ.should eq 98
  cli_list2.bullets[1].y.should eq 98
  srv_list2.delete_bullet srv_list2.all_bullets[0]
  one_exchange(cli, udp_cli, srv)
  cli_list2.bullets.size.should eq 1
  cli_list2.bullets[0].typ.should eq 98
  cli_list2.bullets[0].y.should eq 98
end

def check_rates(n1, n2, nex, srv_list, srv_list2, cli_list, cli_list2, cli, udp_cli, srv)
  srv_list.all_players.clear
  srv_list2.all_bullets.clear
  100.times { one_exchange(cli, udp_cli, srv) }
  cli_list.players.size.should eq 0
  cli_list2.bullets.size.should eq 0
  n1.times { |i| srv_list.new_player("pretty long load#{i}", 99) }
  n2.times { |i| srv_list2.new_bullet(-i) }
  nex.times { one_exchange(cli, udp_cli, srv) }
  {(1.0*cli_list.players.size / n1),
   (1.0*cli_list2.bullets.size / n2)}
end

describe "process large lists" do
  it "initial conditions" do
    srv_list.all_players.clear
    srv_list2.all_bullets.clear
    100.times { one_exchange(cli, udp_cli, srv) }
    cli_list.players.size.should eq 0
    cli_list2.bullets.size.should eq 0
    2.times { |i| srv_list.new_player("todelete#{i}", 99) }
    one_exchange(cli, udp_cli, srv)
    cli_list.players.size.should eq 2
    cli_list2.bullets.size.should eq 0
  end
  it "deletions are passed first, quota is split between lists" do
    outsider = srv_list.all_players[0]
    srv_list.delete_player outsider
    100.times { |i| srv_list.new_player("load#{i}", 99) }
    100.times { |i| srv_list2.new_bullet(-i) }
    one_exchange(cli, udp_cli, srv)
    cli_list.players.count { |pl| pl.name == outsider.name }.should eq 0
    p "over players: #{1.0*srv_list.all_players.size / cli_list.players.size}"
    p "over bullets: #{1.0*srv_list2.all_bullets.size / cli_list2.bullets.size}"
    cli_list.players.size.should be > 2
    cli_list.players.size.should be < 99
    cli_list2.bullets.size.should be > 2
    cli_list2.bullets.size.should be < 99
  end
  it "good coditions, rates 100%" do
    r1, r2 = check_rates(100, 100, 30, srv_list, srv_list2, cli_list, cli_list2, cli, udp_cli, srv)
    r1.should eq 1
    r2.should eq 1
  end
  it "assymmetric good conditions, rates 100%" do
    r1, r2 = check_rates(20, 500, 30, srv_list, srv_list2, cli_list, cli_list2, cli, udp_cli, srv)
    r1.should eq 1
    r2.should eq 1
    r1, r2 = check_rates(500, 20, 30, srv_list, srv_list2, cli_list, cli_list2, cli, udp_cli, srv)
    r1.should eq 1
    r2.should eq 1
  end
  it "severe conditions" do
    r1, r2 = check_rates(1000, 1000, 30, srv_list, srv_list2, cli_list, cli_list2, cli, udp_cli, srv)
    pp r1, r2
    r1.should be > 0.5
    r2.should be > 0.5
  end
end

N1 = 100
N2 = 100
it "benchmark of lists" do
  # ensure there is enough payload in lists
  if srv_list.all_players.size < 1000
    (1000 - srv_list.all_players.size).times { |i| srv_list.new_player("pretty long load#{i}", 99) }
  end
  if srv_list2.all_bullets.size < 1000
    (1000 - srv_list2.all_bullets.size).times { |i| srv_list2.new_bullet(-i) }
  end
  srv.disconnect_delay = 2*60
  clients = [] of TestClientEndpoint
  udps = [] of MySync::UDPGameClient | TestServer
  N1.times do |i|
    acli = TestClientEndpoint.new
    audp_cli = MySync::UDPGameClient.new(acli, Socket::IPAddress.new("127.0.0.1", 12000 + 3))
    acli.sync_lists << ClientPlayersList.new(acli.time)
    acli.sync_lists << ClientBulletsList.new(acli.time)
    do_login(audp_cli, srv, users, public_key, "listsbench#{i}")
    acli.benchmark = N2
    audp_cli.autosend_delay = 1
    # acli.fading_delay = 2.seconds
    clients << acli
    udps << audp_cli
  end
  udps << srv
  start = Time.now
  TimeEmulation.start(udps)
  clients.each do |acli|
    acli.benchmark_complete.receive
  end
  TimeEmulation.stop
  t = (Time.now - start) / N1 / N2
  p "time in ticks: #{(clients.sum &.stat_pingtime) / N1}"
  p "time per packet: #{t.total_milliseconds*1000} us"
end
