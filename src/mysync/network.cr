require "socket"

module MySync
  alias Address = Socket::IPAddress
  alias AddressHash = LibC::Sockaddr
  RIGHT_SIGN       = 0xC4AC7BEu32
  DISCONNECT_DELAY = Time::Span.new(0, 0, 1)

  def self.addr_hash(addr : Address) : AddressHash
    addr.to_unsafe.value
  end
end
