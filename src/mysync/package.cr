# buffer of fixed size + slice of variable size
# TODO: make it looks like a normal slice

class Package
  getter slice : Bytes
  getter base : Bytes

  def initialize(buffer_size : Int32)
    @base = Bytes.new(buffer_size)
    @slice = @base
  end

  def size=(avalue)
    @slice = @base[0, avalue]
  end

  def size
    @slice.size
  end

  def max_size
    @base.size
  end
end
