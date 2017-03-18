require "cannon"
require "./endpoint_types"
require "./endpoint_interface"
require "./circular"
require "./stats"
require "./async_command"

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
  ackrecord LocalAckData, sent : Time, commands : Array(PackedCommand)

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

    @ping_time = FilteredAVG.new
    @losses = CountingAVG.new

    def stat_pingtime
      @ping_time.value
    end

    def stat_losses
      @losses.value
    end

    private def packet_acked(data : LocalAckData)
      @ping_time.add(Time.now - data.sent)
    end

    def process_receive(data : Bytes) : Nil
      @io_received.reset_to(data)
      header = Cannon.decode @io_received, PacketHeader
      return if header.sequence == self.remote_seq || @remote_acks.passed(header.sequence)
      # process acks of remote packets
      most_recent = self.remote_seq < header.sequence
      if most_recent
        self.remote_seq = header.sequence
      end
      @remote_acks.set_passed(header.sequence, true)
      # process acks mask of our packets
      @local_acks.apply_mask(header.ack, header.ack_mask) { |data| packet_acked(data) }

      @remote_sync = Cannon.decode @io_received, RemoteSync
      on_received_sync if most_recent # TODO add size field to skip decoding OoO packets?

      # TODO - process async
    end

    def process_sending : Bytes
      @io_tosend.rewind
      @losses.add !@local_acks.passed(self.local_seq - (N_ACKS - 2))
      # restart non acked commands
      if data = @local_acks[self.local_seq - (N_ACKS - 2)]?
        data.commands.each { |cmd| @async_buffer.push cmd }
      end
      self.local_seq += 1
      # asyncs =
      @local_acks[self.local_seq] = LocalAckData.new(false, Time.now, [] of PackedCommand)
      header = PacketHeader.new(self.local_seq, self.remote_seq, @remote_acks.passed_mask)
      Cannon.encode @io_tosend, header
      before_sending_sync
      Cannon.encode @io_tosend, @local_sync
      # TODO - process async
      return Bytes.new(@io_tosend.buffer, @io_tosend.pos)
    end
  end
end
