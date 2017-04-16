require "../uniqid"

module MySync
  module EndPointFactory
    getter sync_lists = SyncListsManager.new
  end

  abstract class EndPoint
    getter sync_lists_serverside = Hash(ServerSyncList, SyncListEndpointSpecific).new
    property! sync_lists : SyncListsManager

    def receive_lists(io)
      sync_lists.process_received(io)
    end

    def acked_lists(data : LocalAckData)
      # TODO
    end

    def send_lists(io)
      sync_lists.generate_message(self, io)
    end

    def send_lists_partial(io, max_pos)
      sync_lists.generate_message_partial(self, io, max_pos)
    end
  end

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
    getter cur_updated = Set(ItemID).new
    getter cur_deleted = Set(ItemID).new
    property full_size = 0
    property scroll = 0
  end

  # class representing syncronized list of entities on server
  # server-wide part, has `iterate` method that iterates over them for a given client
  # it has `process_sending` method ?
  # in response it writes to io data that will create, remove or modify items on client.
  #
  # from implementation it requires `full_state` and `delta_state` methods that serialize items
  abstract class ServerSyncList
    abstract def generate_message(who : EndPoint, io : IO)
    abstract def generate_message_partial(who : EndPoint, io : IO, max_pos : Int32)

    # abstract def priority : Int32 TODO: lists prioritization

  end

  module ServerSyncListImplementation(T, FullState, DeltaState)
    abstract def full_state(item : T) : FullState
    abstract def delta_state(old_state : FullState, item : T) : DeltaState
    abstract def iterate(who : EndPoint, &block : T -> Nil)

    # TODO: sort according to time? total mechanism of overflow processing
    def full_message_accepted(who : MySync::EndPoint)
      state = who.sync_lists_serverside[self]
      actual = Time.now
      state.last_updated.reject! { |item| state.cur_deleted.includes? item }
      state.cur_updated.each { |item| state.last_updated[item] = actual }
    end

    def generate_message(who : MySync::EndPoint, io : IO)
      state = who.sync_lists_serverside[self]? || SyncListEndpointSpecific.new.tap do |it|
        who.sync_lists_serverside[self] = it
      end
      old_pos = io.pos
      actual = Time.now
      # addition\update messages
      state.cur_updated.clear
      iterate_additions(io, who, state) do |item|
        state.cur_updated << item.id
        false
      end
      # deletion messages
      state.cur_deleted.clear
      state.last_updated.each do |id, time|
        # state.image...
        next if state.cur_updated.includes? id
        Cannon.encode io, id
        Cannon.encode io, MySync::ChangeType::ItemDeletion.value
        state.cur_deleted << id
      end
      Cannon.encode io, MySync::ItemID.new(0)
      state.full_size = io.pos - old_pos
    end

    # TODO unify interface with full message
    def iterate_additions(io, who, state, scroll : Int32? = nil, &block)
      iterate(who) do |item|
        if scroll && scroll > 0
          scroll -= 1
          next
        end
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
        # state.last_updated[id] = actual
        return if yield(item)
      end
    end

    def generate_message_partial(who : EndPoint, io : IO, max_pos : Int32)
      state = who.sync_lists_serverside[self]
      max_pos -= sizeof(MySync::ItemID)
      # at least transmit deletions as they weights less
      state.cur_deleted.each do |id|
        break if io.pos >= max_pos - 4
        Cannon.encode io, id
        Cannon.encode io, MySync::ChangeType::ItemDeletion.value
        state.last_updated.delete(id)
      end
      if io.pos < max_pos - 4 && !state.cur_updated.empty?
        # process updated items, twice with a random chance of selection, then in normal order
        old_pos = io.pos
        returned_early = false
        2.times do |iter|
          iterate_additions(io, who, state, iter == 0 ? state.scroll : nil) do |item|
            exhausted = io.pos > max_pos
            if exhausted
              io.pos = old_pos
              returned_early = true
            else
              old_pos = io.pos
              state.last_updated[item.id] = Time.now
              state.scroll += 1
            end
            exhausted
          end
          break if returned_early || io.pos >= max_pos
          state.scroll = 0
        end
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

    def full_message_accepted(who)
      @server_lists.each { |list| list.full_message_accepted(who) }
    end

    def generate_message_partial(who, io : IO, max_size)
      # priorities would go here
      start = io.pos
      total = @server_lists.sum { |list| who.sync_lists_serverside[list].full_size }
      return if total == 0
      rate = (100*max_size / total).clamp(1, 100)
      @server_lists.each { |list|
        last = list == @server_lists.last
        if last
          chunk = max_size - (io.pos - start)
        else
          chunk = rate * who.sync_lists_serverside[list].full_size / 100
        end
        list.generate_message_partial who, io, io.pos + chunk
      }
      raise "partial list generation failed pos=#{io.pos} start=#{start} max_size=#{max_size}" if io.pos > start + max_size
    end
  end
end
