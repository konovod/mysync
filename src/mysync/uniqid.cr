module MySync
  alias ItemID = UInt16

  # TODO - specs
  # TODO - better name, lol?
  class IDS
    @counter = ItemID.new(0)
    @used = Set(ItemID).new

    def generate
      started = @counter
      @counter += 1
      while @counter == 0 || @used.includes?(@counter)
        @counter += 1
        raise "can't find free id" if @counter == started
      end
      @used << @counter
      return @counter
    end

    def recycle(id : ItemID)
      @used.delete @counter
    end
  end
end
