class FilteredAVG
  getter value : Float64

  def initialize(@filter : Float64 = 0.9)
    @value = 0.0
  end

  def add(v)
    @value = @filter * @value + (1 - @filter)*v.to_f
  end
end

class CountingAVG
  getter value : Float64

  def initialize(@max = 100)
    @total = 0
    @positive = 0
    @value = 0.0
  end

  def add(value : Bool)
    @total += 1
    @positive += 1 if value
    if @total >= @max
      @value = 1.0*@positive / @total
      @total = 0
      @positive = 0
    end
  end
end
