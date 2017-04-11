require "cannon"
require "./endpoint_types"
require "./circular"
require "./stats"
require "./payloads/commands"
require "./payloads/rpc"
require "./payloads/lists"
require "./payloads/sync"

module MySync
  module EndPointFactory
    abstract def new_endpoint(authdata : Bytes) : {endpoint: EndPoint?, response: Bytes}
    abstract def on_connecting(ip : Address)
    abstract def on_disconnecting(ip : Address, ex : Exception?)
  end

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
  abstract class EndPoint
    ackrecord RemoteAckData
    ackrecord LocalAckData, sent : Time = Time.new, commands = [] of Command

    getter requested_disconnect : Bool
    getter cmd_buffer = CommandBuffer.new

    def initialize
      super
      @requested_disconnect = false
      @io_received = MyMemory.new(1)
      @io_tosend = IO::Memory.new(MAX_PACKAGE_SIZE)
      @remote_acks = CircularAckBuffer(RemoteAckData).new
      @local_acks = CircularAckBuffer(LocalAckData).new
    end

    def on_received_package
    end

    def before_sending_package
    end

    def on_disconnect
    end

    def reset
      @local_acks.reset
      @remote_acks.reset
      @remote_message_acks.reset
      @requested_disconnect = false
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
      data.commands.each { |cmd| @cmd_buffer.acked cmd }
    end

    def process_receive(data : Bytes) : Nil
      @io_received.reset_to(data)
      header = Cannon.decode @io_received, PacketHeader
      if header.sequence == self.remote_seq || @remote_acks.passed(header.sequence)
        p "discarding duplicate #{header.sequence} at #{self.remote_seq}"
        return
      end
      # process acks of remote packets
      delta = SequenceSigned.new(header.sequence - self.remote_seq)
      if delta < -N_ACKS + 1 # too_old
        p "discarding as old #{delta}"
        return
      end
      most_recent = delta >= 0
      if most_recent
        self.remote_seq = header.sequence
      end
      @remote_acks.set_passed(header.sequence, true)
      # process acks mask of our packets
      @local_acks.apply_mask(header.ack, header.ack_mask) { |data| packet_acked(data) }

      # reading payloads
      receive_sync # TODO add size field to skip decoding OoO packets?
      receive_asyncs
      if most_recent
        receive_lists
        # and finally call callback
        on_received_package
      end
    end

    def process_sending : Bytes
      @io_tosend.rewind
      @losses.add !@local_acks.passed(self.local_seq - (N_ACKS - 2))
      self.local_seq += 1
      cur_commands = [] of Command
      @local_acks[self.local_seq] = LocalAckData.new(false, Time.now, cur_commands)
      header = PacketHeader.new(self.local_seq, self.remote_seq, @remote_acks.passed_mask)
      Cannon.encode @io_tosend, header

      # sending payloads
      before_sending_package
      send_sync
      # TODO - check if too big and split
      send_asyncs(cur_commands)
      send_lists

      return @io_tosend.to_slice
    end
  end
end
