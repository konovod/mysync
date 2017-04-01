require "./spec_helper"
require "../src/mysync/lists"
require "../src/mysync/uniqid"

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

# class Bullet < MySync::IdItem
#   property x = 0
#   property y = 0
# end
#

class ClientPlayersList < MySync::ClientSyncList
  client_generics_crunch(Player, PlayerAdder, PlayerUpdater)
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

class ServerPlayersList < MySync::ServerSyncList(Player, PlayerAdder, PlayerUpdater)
  getter all_players = [] of Player
  @uids = MySync::IDS.new

  def full_state(item)
    FullState.new(item.name, item.hp)
  end

  def delta_state(old_state, item)
    DeltaState.new(item.hp)
  end

  def iterate(who, &block)
    @all_players.each { |pl| yield(pl) }
  end

  def new_player(name, hp)
    all_players << Player.new(@uids.generate, name, hp)
  end

  def delete_player(player)
    all_players.delete player
    @uids.recycle player.id
  end

  # fix for a https://github.com/crystal-lang/crystal/issues/4224
  def generate_message(*args)
    super(args)
  end
end

cli_list = ClientPlayersList.new
srv_list = ServerPlayersList.new

cli, udp_cli, srv, udp_srv, public_key = make_test_pair(3)
cli.sync_lists << cli_list
srv.sync_lists << srv_list

udp_cli.login(public_key, Bytes.new(1))
one_login(udp_cli)
srv_inst = srv.test_endpoint.not_nil!

it "starts empty" do
  cli_list.players.size.should eq 0
  srv_list.all_players.size.should eq 0
end

it "syncs added elements" do
  srv_list.new_player("test", 99)
  one_exchange(cli, udp_cli)
  cli_list.players.size.should eq 1
  cli_list.players[0].name.should eq "test"
  cli_list.players[0].hp.should eq 99
end
