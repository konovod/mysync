require "spec"
require "../src/mysync"
require "../src/mysync/basic"
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
  include MySync::CachedIO
  def initialize(@cliio : IO, @srvio : IO, @server : MySync::Server)
  end

  def perform
    @server.process_request(@srvio)
  end

  def read(slice : Bytes)
    return @cliio.read(slice)
  end

  def write(slice : Bytes)
    @cliio.write(slice)
  end

end

def virtual_connect(srv : MySync::Server)
  #pipe is useless at all - sync and no binary
  # IO.pipe do |x,y|
  #   yield(x,y)
  # end
  data = Bytes.new(1000)
  io1 = SimpleSliceIO.new(data)
  io2 = SimpleSliceIO.new(data)
  VirtualIO.new(io1,io2,srv)
end
