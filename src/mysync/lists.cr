module MySync
  alias ItemID = UInt16

  class ListItem
    property id : MySync::ItemID = 0u16

    def initialize(@id)
    end
  end

  # class representing syncronized list of entities on client
  # it receives packets and parse them to calls of `item_added`, `item_removed` and `item_updated`
  abstract class ClientSyncList(T, FullState, DeltaState)
    @items = Hash(ItemID, T).new
    @last_updated = Hash(ItemID, Time).new

    abstract def item_added(id : ItemID, data : FullState) : T
    abstract def item_removed(item : T)
    abstract def item_updated(item : T, data : DeltaState)

    def process_received(io : IO)
      # TODO
    end
  end

  # class representing syncronized list of entities on server
  # it has `process_sending` method ?
  # in response it writes to io data that will create, remove or modify items on client.
  #
  # from implementation it requires `full_state` and `delta_state` methods that serialize items

  class ServerConnectionSyncList
    @items = Hash(ItemID, ListItem).new
    @last_updated = Hash(ItemID, Time).new
  end

  abstract class ServerSyncList(T, FullState, DeltaState)
    abstract def full_state(item : T) : FullState
    abstract def delta_state(old_state : FullState, item : T) : DeltaState
    abstract def iterate(who : GameConnection, &block : T -> Nil)
    # abstract def priority : Int32 TODO: lists prioritization

  end

  # class representing syncronized list of entities on server
  # server-wide part, has `iterate` method that iterates over them for a given client
  abstract class ServerSyncList
  end
end
