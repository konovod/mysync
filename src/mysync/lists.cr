require "./uniqid"

module MySync
  class ListItem
    property id : ItemID

    def initialize(@id)
    end
  end

  enum ChangeType : UInt8
    ItemAddition
    ItemDeletion
    ItemUpdate
  end

  # class representing syncronized list of entities on client
  # it receives packets and parse them to calls of `item_added`, `item_removed` and `item_updated`
  abstract class ClientSyncList
    @last_updated = Hash(ItemID, Time).new
    property fading_delay : Time::Span = 1.seconds

    abstract def process_received(io : IO)
    abstract def item_added(id : ItemID, data)
    abstract def item_removed(item)
    abstract def item_updated(item, data)

    def check_fading
      actual = Time.now
      @last_updated.reject! do |id, time|
        flag = actual - time > fading_delay
        if flag
          item = @items.delete(id)
          item_removed(item) if item
        end
      end
    end
  end

  module SyncListData(T, FullState, DeltaState)
    @items = Hash(MySync::ItemID, T).new

    def process_received(io : IO)
      actual = Time.now
      while io.pos < io.size
        id = Cannon.decode(io, MySync::ItemID)
        break if id == 0
        typ = MySync::ChangeType.new(Cannon.decode(io, UInt8))
        case typ
        when MySync::ChangeType::ItemAddition
          full = Cannon.decode(io, FullState)
          if old_item = @items[id]?
            item_removed(old_item)
          end
          @items[id] = item_added(id, full)
          @last_updated[id] = actual
        when MySync::ChangeType::ItemUpdate
          delta = Cannon.decode(io, DeltaState)
          item = @items[id]?
          if item
            item_updated(item, delta)
          else
            p "ignoring failed delta" # TODO - better log?
          end
          @last_updated[id] = actual
        when MySync::ChangeType::ItemDeletion
          item = @items.delete(id)
          @last_updated.delete(id)
          item_removed(item) if item
        end
      end
      check_fading
    end
  end

  # class representing syncronized list of entities on server
  # part with connection data
  class SyncListEndpointSpecific
    # @image = Hash(ItemID, FullState).new TODO - lol, system is broken again
    getter last_updated = Hash(ItemID, Time).new
  end

  # class representing syncronized list of entities on server
  # server-wide part, has `iterate` method that iterates over them for a given client
  # it has `process_sending` method ?
  # in response it writes to io data that will create, remove or modify items on client.
  #
  # from implementation it requires `full_state` and `delta_state` methods that serialize items
  abstract class ServerSyncList
    abstract def generate_message(who : EndPoint, io : IO)

    # abstract def priority : Int32 TODO: lists prioritization

  end

  module ServerSyncListImplementation(T, FullState, DeltaState)
    abstract def full_state(item : T) : FullState
    abstract def delta_state(old_state : FullState, item : T) : DeltaState
    abstract def iterate(who : EndPoint, &block : T -> Nil)

    # TODO: sort according to time? total mechanism of overflow processing
    def generate_message(who : MySync::EndPoint, io : IO)
      state = who.sync_lists_serverside[self]? || SyncListEndpointSpecific.new.tap do |it|
        who.sync_lists_serverside[self] = it
      end
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
        Cannon.encode io, MySync::ChangeType::ItemAddition.value
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
          Cannon.encode io, MySync::ChangeType::ItemDeletion.value
        end
        flag
      end
      Cannon.encode io, MySync::ItemID.new(0)
    end
  end

  class SyncListsManager
    @client_lists = [] of ClientSyncList
    @server_lists = [] of ServerSyncList

    def <<(item : (ServerSyncList | ClientSyncList))
      case item
      when ServerSyncList
        @server_lists << item
      when ClientSyncList
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
