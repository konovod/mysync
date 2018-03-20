alias CrystalTime = Time

module MySync
  alias GameTime = UInt32
  alias TimeDelta = Int32
  SECOND = 60
  TICK   = (1.0/SECOND).seconds

  class TimeProvider
    property current : GameTime = GameTime.new(0)

    def delta(value : GameTime) : TimeDelta
      TimeDelta.new(value - current)
    end
  end
end
