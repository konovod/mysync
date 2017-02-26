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

  private class MyMemory < IO::Memory
    def reset_to(slice : Bytes)
      @buffer = slice.to_unsafe
      @bytesize = @capacity = slice.size.to_i
      @pos = 0
    end
  end

  abstract class AbstractEndPoint
    getter requested_disconnect : Bool

    def initialize
      @requested_disconnect = false
    end

    abstract def process_receive(data : Bytes) : Nil
    abstract def process_sending : Bytes

    def on_disconnect
    end
  end

  module EndPointFactory
    abstract def new_endpoint(authdata : Bytes) : {endpoint: AbstractEndPoint, response: Bytes}?
  end

  abstract class EndPoint(LocalSync, RemoteSync) < AbstractEndPoint
    property local_sync : LocalSync
    property remote_sync : RemoteSync
    property local_seq : Sequence
    property remote_seq : Sequence

    def initialize
      super
      @io_received = MyMemory.new(1)
      @io_tosend = IO::Memory.new(MAX_PACKAGE_SIZE)
      @local_sync = LocalSync.new
      @remote_sync = RemoteSync.new
      @local_seq = 0u16
      @remote_seq = 0u16
    end

    abstract def on_received_sync
    abstract def before_sending_sync

    def process_receive(data : Bytes) : Nil
      @io_received.reset_to(data)
      header = Cannon.decode @io_received, PacketHeader
      return if header.sequence == @remote_seq
      if @remote_seq < header.sequence
        @remote_seq = header.sequence
        # TODO - process own ack_mask
      else
      end
      # TODO - process packet acks
      @remote_sync = Cannon.decode @io_received, RemoteSync
      on_received_sync
      # TODO - process async
    end

    def process_sending : Bytes
      @io_tosend.rewind
      # TODO - fill ack_mask
      @local_seq += 1
      header = PacketHeader.new(@local_seq, @remote_seq, 0u32)
      Cannon.encode @io_tosend, header
      before_sending_sync
      Cannon.encode @io_tosend, @local_sync
      # TODO - process async
      return Bytes.new(@io_tosend.buffer, @io_tosend.pos)
    end
  end

  # abstract class AsyncCommand
  #   abstract def perform(user : UserContext)
  # end

end
