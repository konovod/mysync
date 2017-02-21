require "./spec_helper"

describe "additions to cannon" do
  io = IO::Memory.new(100)
  it "StaticArray of ints" do
    data = StaticArray(Int32, 16).new(15)
    Cannon.encode(io, data)
    io.rewind
    data2 = Cannon.decode(io, typeof(data))
    io.rewind
    data2.should eq data
  end
  it "StaticArray of strings" do
    data = StaticArray(String, 16).new("15")
    Cannon.encode(io, data)
    io.rewind
    data2 = Cannon.decode(io, typeof(data))
    io.rewind
    data2.should eq data
  end
end
