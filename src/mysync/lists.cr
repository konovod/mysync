module MySync
  alias ItemID = UInt16

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
  abstract class ServerSyncList(T, FullState, DeltaState)
    @items = Hash(ItemID, T).new
    @last_updated = Hash(ItemID, Time).new

    abstract def full_state(item : T) : FullState
    abstract def delta_state(old_state : FullState, item : T) : DeltaState
    # abstract def priority : Int32 TODO: lists prioritization

  end

  class SyncListsManager
  end
end
