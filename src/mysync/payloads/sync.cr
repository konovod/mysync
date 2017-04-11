# require "../endpoint_types"

module MySync
  abstract class EndPoint
    abstract def receive_sync
    abstract def send_sync
  end
end

macro set_local_sync(typ)
  property local_sync : {{typ}} = {{typ}}.new
  def send_sync
    Cannon.encode @io_tosend, @local_sync
  end
end

macro set_remote_sync(typ)
  property remote_sync : {{typ}} = {{typ}}.new
  def receive_sync
    @remote_sync = Cannon.decode @io_received, typeof(@remote_sync)
  end
end
