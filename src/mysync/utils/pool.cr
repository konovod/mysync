class LinearPool(T)
  @items = [] of T
  @active = 0

  def reset
    @active = 0
  end

  def size
    @items.size
  end

  def get(&block)
    @items << yield if @active == @items.size
    result = @items[@active]
    @active += 1
    result
  end

  def get
    get { T.new }
  end
end

class Pool(T)
  @items = [] of T
  @available = [] of T

  def reset
    @available = @items.dup
  end

  def size
    @items.size
  end

  def get(&block)
    item = @available.pop? || yield().tap { |it| @items << it }
  end

  def recycle(item)
    @available << item
  end

  def get
    get { T.new }
  end
end
