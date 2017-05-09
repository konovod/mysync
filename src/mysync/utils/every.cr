def every(timespan, &block)
  tick = Time.now
  loop do
    passed = Time.now - tick
    while passed > timespan
      yield()
      passed -= timespan
      tick += timespan
    end
    sleep({timespan - passed, 0.seconds}.max)
  end
end
