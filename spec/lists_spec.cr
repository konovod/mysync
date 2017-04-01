require "./spec_helper"
require "../src/mysync/lists"

# on client side - client contains lists manager, inside there are lists.
# There are commands to make, remove and update items

class Player < MySync::ListItem
  property name = ""
  property hp = 100
end

record PlayerAdder, name : String, hp : Int32
record PlayerUpdater, hp : Int32

# class Bullet < MySync::IdItem
#   property x = 0
#   property y = 0
# end
#

class ClientPlayersList < MySync::ClientSyncList(Player, PlayerAdder, PlayerUpdater)
  getter players = [] of Player

  def item_added(id, data)
    Player.new(id).tap do |player|
      players << player
      player.name = data.name
      player.hp = data.hp
    end
  end

  def item_removed(item)
    players.delete player
  end

  def item_updated(item, data)
    player.hp = data.hp
  end
end

class ServerPlayersList < MySync::ServerSyncList(Player, PlayerAdder, PlayerUpdater)
  getter all_players = [] of Player

  def full_state(item)
    FullState.new(item.name, item.hp)
  end

  def delta_state(old_state, item)
    DeltaState.new(item.hp)
  end

  def iterate(who, &block)
    @all_players.each { |pl| yield(pl) }
  end
end

cli_list = ClientPlayersList.new
srv_list = ServerPlayersList.new

cli, udp_cli, srv, udp_srv, public_key = make_test_pair(1)
cli.sync_lists << cli_list
srv.sync_lists << srv_list

udp_cli.login(public_key, Bytes.new(1))
one_login(udp_cli)
srv_inst = srv.test_endpoint.not_nil!

it "starts empty" do
  cli_list.players.size.should eq 0
  srv_list.all_players.size.should eq 0
end
