module MySync
  alias ItemID = UInt16

  class ListItem
    property id : MySync::ItemID = 0u16

    def initialize(@id)
    end
  end

  abstract class AbstractClientSyncList
    abstract def process_received(io : IO)
  end

  # class representing syncronized list of entities on client
  # it receives packets and parse them to calls of `item_added`, `item_removed` and `item_updated`
  abstract class ClientSyncList(T, FullState, DeltaState) < AbstractClientSyncList
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
  # part with connection data
  class ServerConnectionSyncList
    @items = Hash(ItemID, ListItem).new
    @last_updated = Hash(ItemID, Time).new
  end

  abstract class AbstractServerSyncList
    abstract def generate_message(io : IO)
  end

  # class representing syncronized list of entities on server
  # server-wide part, has `iterate` method that iterates over them for a given client
  # it has `process_sending` method ?
  # in response it writes to io data that will create, remove or modify items on client.
  #
  # from implementation it requires `full_state` and `delta_state` methods that serialize items
  abstract class ServerSyncList(T, FullState, DeltaState) < AbstractServerSyncList
    abstract def full_state(item : T) : FullState
    abstract def delta_state(old_state : FullState, item : T) : DeltaState
    abstract def iterate(who : GameConnection, &block : T -> Nil)

    # abstract def priority : Int32 TODO: lists prioritization
    def generate_message(io : IO)
      # TODO
    end
  end

  class SyncListsManager
    @client_lists = [] of AbstractClientSyncList
    @server_lists = [] of AbstractServerSyncList

    def <<(item : (AbstractServerSyncList | AbstractClientSyncList))
      if item.is_a? AbstractServerSyncList
        @server_lists << item
      else
        @client_lists << item
      end
    end

    def process_received(io : IO)
      @client_lists.each { |list| list.process_received io }
    end

    def generate_message(io : IO)
      @server_lists.each { |list| list.generate_message io }
    end
  end
end
