require "socket"

module MySync
  alias Address = Socket::IPAddress
  RIGHT_SIGN       = 0xC4AC7BE
  DISCONNECT_DELAY = Time::Span.new(0, 0, 1)
end
