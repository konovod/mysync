module MySync
  alias ItemID = UInt16

  # TODO - specs
  # TODO - better implementation, this one is broken
  # TODO - better name, lol?
  class IDS
    @counter = ItemID.new(0)

    def generate
      @counter += 1
      @counter += 1 if @counter == 0
      return @counter
    end

    def recycle(id : ItemID)
    end
  end
end
