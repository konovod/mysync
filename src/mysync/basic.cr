require "cannon"

module MySync

alias UserID = Int32

@[Packed]
struct PacketHeader
  include Cannon::FastAuto
  property signature : Int32
  property sequence : UInt16
  property ack : UInt16
  property ack_mask : UInt32
  def initialize
    @signature = 0
    @sequence = 0u16
    @ack = 0u16
    @ack_mask = 0u32
  end
end

PACKAGE_SIZE = 1024


abstract class EndPoint(LocalSync, RemoteSync)
  property local_sync : LocalSync
  property remote_sync : RemoteSync

  getter package_received
  getter package_tosend

  def initialize
    @local_sync = LocalSync.new
    @remote_sync = RemoteSync.new
    @package_received = Bytes.new(PACKAGE_SIZE)
    @io_received = IO::Memory.new(@package_received)
    @package_tosend = Bytes.new(PACKAGE_SIZE)
    @io_tosend = IO::Memory.new(@package_tosend)
  end

  abstract def on_received_sync
  abstract def before_sending_sync

  def process_receive
    @io_received.rewind
    header = Cannon.decode @io_received, PacketHeader
    #TODO - process header
    @remote_sync = Cannon.decode @io_received, RemoteSync
    on_received_sync
    #TODO - process async
  end

  def process_sending : Int32
    @io_tosend.rewind
    #TODO - make header
    header = PacketHeader.new
    Cannon.encode @io_tosend, header
    before_sending_sync
    Cannon.encode @io_tosend, @local_sync
    #TODO - process async
    return @io_tosend.pos
  end
end


# abstract class AsyncCommand
#   abstract def perform(user : UserContext)
# end


end
