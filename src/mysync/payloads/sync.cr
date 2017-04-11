# require "../endpoint_types"

module MySync
  abstract class EndPoint
    abstract def receive_sync(io : IO)
    abstract def send_sync(io : IO)
  end
end

macro set_local_sync(typ)
  property local_sync : {{typ}} = {{typ}}.new
  def send_sync(io)
    Cannon.encode io, @local_sync
  end
end

macro set_remote_sync(typ)
  property remote_sync : {{typ}} = {{typ}}.new
  def receive_sync(io)
    @remote_sync = Cannon.decode io, typeof(@remote_sync)
  end
end
