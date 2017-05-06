alias CrystalTime = Time

module MySync
  alias Time = UInt32
  alias TimeDelta = Int32
  SECOND = 60
  TICK   = (1.0/SECOND).seconds

  class TimeProvider
    property current : Time = Time.new(0)

    def delta(value : Time) : TimeDelta
      TimeDelta.new(value - current)
    end
  end
end
