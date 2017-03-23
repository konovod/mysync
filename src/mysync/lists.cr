module MySync
  abstract class AbstractSyncList
    abstract def iterate(&block)
    abstract def item_size : Int32
    # abstract def data : Bytes TODO - do it later to optimize writing
  end

  abstract class SyncList(T)
    def initialize(@data : Array(T))
    end

    abstract def visible(item : T) : Bool

    # abstract def priority : Int32 TODO: lists prioritization

    def iterate(&block)
      @data.each { |item| yield(item) if visible(item) }
    end

    def item_size
      sizeof(T)
    end
  end

  class SyncListsManager
  end
end
