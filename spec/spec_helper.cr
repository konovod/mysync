require "spec"
require "../src/mysync"
require "socket"


class SimpleSliceIO
  include IO

  def initialize(@slice : Bytes)
  end

  def read(slice : Bytes)
    slice.size.times { |i| slice[i] = @slice[i] }
    @slice += slice.size
    slice.size
  end

  def write(slice : Bytes)
    slice.size.times { |i| @slice[i] = slice[i] }
    @slice += slice.size
    nil
  end
end

class VirtualIO
  include IO
  def initialize(@cliio : IO, @srvio : IO, @server : MySync::Server)
    @processed = false
  end

  def read(slice : Bytes)
    unless @processed
      @processed = true
      @server.process_request(@srvio)
    end
    return @cliio.read(slice)
  end

  def write(slice : Bytes)
    @cliio.write(slice)
  end

end

def virtual_server(srv : MySync::Server, &block)
  #pipe is useless at all
  # IO.pipe do |x,y|
  #   yield(x,y)
  # end
  data = Bytes.new(1000)
  io1 = SimpleSliceIO.new(data)
  io2 = SimpleSliceIO.new(data)
  yield(MySync::Client.new(VirtualIO.new(io1,io2,srv)))

end
