def every(timespan, &block)
  tick = Time.now
  loop do
    passed = Time.now - tick
    while passed > timespan
      yield()
      Fiber.yield # prevent monopolization
      passed -= timespan
      tick += timespan
    end
    sleep({timespan - passed, 0.01.seconds}.max) # TODO - check if 0 passes specs
  end
end
