def every(timespan, &block)
  tick = Time.utc
  loop do
    passed = Time.utc - tick
    while passed > timespan
      yield()
      passed -= timespan
      tick += timespan
    end
    sleep({timespan - passed, 0.seconds}.max)
  end
end
