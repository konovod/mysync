require "cannon"
require "./endpoint_types"
require "./endpoint_interface"
require "./circular"

module MySync
  MAX_PACKAGE_SIZE = 1024

  @[Packed]
  record PacketHeader, sequence : Sequence, ack : Sequence, ack_mask : AckMask do
    include Cannon::FastAuto
  end

  # IO::Memory refinement that can change used buffer avoiding reallocation
  private class MyMemory < IO::Memory
    def reset_to(slice : Bytes)
      @buffer = slice.to_unsafe
      @bytesize = @capacity = slice.size.to_i
      @pos = 0
    end
  end

  # for our packets we save a time to measure ping
  # for remote we need only the fact that it passed
  ackrecord RemoteAckData
  ackrecord LocalAckData, sent : Time

  abstract class EndPoint(LocalSync, RemoteSync) < AbstractEndPoint
    property local_sync : LocalSync
    property remote_sync : RemoteSync

    def initialize
      super
      @io_received = MyMemory.new(1)
      @io_tosend = IO::Memory.new(MAX_PACKAGE_SIZE)
      @local_sync = LocalSync.new
      @remote_sync = RemoteSync.new
      @remote_acks = CircularAckBuffer(RemoteAckData).new
      @local_acks = CircularAckBuffer(LocalAckData).new
    end

    def local_seq : Sequence
      @local_acks.cur_seq
    end

    def remote_seq : Sequence
      @remote_acks.cur_seq
    end

    # TODO - do we need them? only for spec? mock?
    def local_seq=(value : Sequence)
      @local_acks.cur_seq = value
    end

    def remote_seq=(value : Sequence)
      @remote_acks.cur_seq = value
    end

    abstract def on_received_sync
    abstract def before_sending_sync

    private def packet_acked(data : LocalAckData)
    end

    def process_receive(data : Bytes) : Nil
      @io_received.reset_to(data)
      header = Cannon.decode @io_received, PacketHeader
      return if header.sequence == self.remote_seq || @remote_acks.passed(header.sequence)
      # now process packet acks
      if self.remote_seq < header.sequence
        self.remote_seq = header.sequence
        # TODO - measure percent of loss?
      end
      @remote_acks.set_passed(header.sequence, true)
      # TODO - now process packet acks
      if header.ack > self.local_seq
        self.local_seq = header.ack
        packet_acked(@local_acks[header.ack]?.not_nil!)
      end
      @local_acks.apply_mask(header.ack_mask) { |data| packet_acked(data) }

      @remote_sync = Cannon.decode @io_received, RemoteSync
      on_received_sync
      # TODO - process async
    end

    def process_sending : Bytes
      @io_tosend.rewind
      self.local_seq += 1
      header = PacketHeader.new(self.local_seq, self.remote_seq, @remote_acks.passed_mask)
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
