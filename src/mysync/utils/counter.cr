class EventCounter
  getter value = 0

  def initialize
    @time = Time.now
    @cur_value = 0
    @value = 0
  end

  def value
    update
    @value
  end

  private def update
    now = Time.now
    if now - @time > 1.seconds
      @value = @cur_value
      @cur_value = 0
      @time = now
    end
  end

  def inc
    @cur_value += 1
    update
  end
end
