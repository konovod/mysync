require "cannon"

module MySync

alias UserID = Int32
alias Sequence = UInt16
alias AckMask = UInt32

MAX_PACKAGE_SIZE = 1024




@[Packed]
struct PacketHeader
  include Cannon::FastAuto
  property sequence : Sequence
  property ack : Sequence
  property ack_mask : AckMask
  def initialize(@sequence, @ack, @ack_mask)
  end
end


abstract class AbstractEndPoint
end

abstract class EndPoint(LocalSync, RemoteSync) < AbstractEndPoint
  property local_sync : LocalSync
  property remote_sync : RemoteSync
  property local_seq : Sequence
  property remote_seq : Sequence

  getter package_received
  getter package_tosend

  def initialize
    @local_sync = LocalSync.new
    @remote_sync = RemoteSync.new
    @package_received = Bytes.new(MAX_PACKAGE_SIZE)
    @io_received = IO::Memory.new(@package_received)
    @package_tosend = Bytes.new(MAX_PACKAGE_SIZE)
    @io_tosend = IO::Memory.new(@package_tosend)
    @local_seq = 0u16
    @remote_seq = 0u16
  end

  abstract def on_received_sync
  abstract def before_sending_sync

  def process_receive
    @io_received.rewind
    header = Cannon.decode @io_received, PacketHeader
    return if header.sequence == @remote_seq
    if @remote_seq < header.sequence
      @remote_seq = header.sequence
      #TODO - process own ack_mask
    else
    end
    #TODO - process packet acks
    @remote_sync = Cannon.decode @io_received, RemoteSync
    on_received_sync
    #TODO - process async
  end

  def process_sending : Int32
    @io_tosend.rewind
    #TODO - fill ack_mask
    @local_seq += 1
    header = PacketHeader.new(@local_seq, @remote_seq, 0u32)
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
