

module MySync


class UDPClientIO
  include IO

  def initialize(@udp : UDPSocket)
  end

  def read(slice : Bytes)
    return @udp.read(slice)
  end

  def write(slice : Bytes)
    
  end

end



end
