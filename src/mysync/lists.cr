require "./uniqid"

module MySync
  class ListItem
    property id : ItemID

    def initialize(@id)
    end
  end

  abstract class AbstractClientSyncList
    abstract def process_received(io : IO)
  end

  enum ChangeType : UInt8
    ItemAddition
    ItemDeletion
    ItemUpdate
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
      while io.pos < io.size
        id = Cannon.decode(io, ItemID)
        break if id == 0
        typ = ChangeType.new(Cannon.decode(io, UInt8))
        case typ
        when ChangeType::ItemAddition
          full = Cannon.decode(io, FullState)
          if old_item = @items[id]?
            item_removed(old_item)
          end
          @items[id] = item_added(id, full)
        when ChangeType::ItemUpdate
          delta = Cannon.decode(io, DeltaState)
          item = @items[id]?
          if item
            item_updated(item, delta)
          else
            p "ignoring failed delta" # TODO
          end
        when ChangeType::ItemDeletion
          item = @items.delete(id)
          item_removed(item) if item
        end
      end
    end
  end

  # class representing syncronized list of entities on server
  # part with connection data
  class SyncListEndpointSpecific
    # @image = Hash(ItemID, FullState).new TODO - lol, system is broken again
    getter last_updated = Hash(ItemID, Time).new
  end

  abstract class AbstractServerSyncList
    abstract def generate_message(who : EndPoint, io : IO)
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
    abstract def iterate(who : EndPoint, &block : T -> Nil)

    # abstract def priority : Int32 TODO: lists prioritization
    # TODO: sort according to time? total mechanism of overflow processing
    def generate_message(who : EndPoint, io : IO)
      state = who.sync_lists_serverside
      actual = Time.now
      # addition\update messages
      iterate(who) do |item|
        id = item.id
        Cannon.encode io, id
        # old = state.image[id]?
        full = full_state(item)
        # if old
        #   Cannon.encode io, ItemUpdate
        #   Cannon.encode delta_state(old, item)
        # else
        Cannon.encode io, ChangeType::ItemAddition.value
        Cannon.encode io, full
        # end
        # state.image[id] = full
        state.last_updated[id] = actual
      end
      # deletion messages
      state.last_updated.reject! do |id, time|
        # state.image...
        flag = time != actual
        if flag
          Cannon.encode io, id
          Cannon.encode io, ChangeType::ItemDeletion.value
        end
        flag
      end
      Cannon.encode io, ItemID.new(0)
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

    def generate_message(who, io : IO)
      @server_lists.each { |list| list.generate_message who, io }
    end
  end
end
