require "socket"
require "monocypher"
require "./endpoint"

# TODO: alias PoorManEvent = Channel(Nil) or actually use events?
# TODO: utilize inplace encrypt\decrypt

module MySync
  alias Address = Socket::IPAddress
  alias AddressHash = LibC::Sockaddr
  RIGHT_SIGN       = 0xC4AC7BEu32
  RIGHT_LOGIN_SIGN = 0xC4AC7BFu32
  RIGHT_PASS_SIGN  = 0xC4AC7D0u32

  MAX_RAW_SIZE = MAX_PACKAGE_SIZE + 4 + Crypto::OVERHEAD_SYMMETRIC
  MIN_RAW_SIZE = 4 + Crypto::OVERHEAD_SYMMETRIC

  def self.addr_hash(addr : Address) : AddressHash
    addr.to_unsafe.value
  end
end
