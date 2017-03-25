require "cannon"
require "./endpoint_types"
require "./circular"
require "./stats"
require "./commands"
require "./rpc"

module MySync
  module EndPointFactory
    abstract def new_endpoint(authdata : Bytes) : {endpoint: EndPoint, response: Bytes}?
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
  ackrecord RemoteAckData
  ackrecord LocalAckData, sent : Time = Time.new, commands = [] of Command
  ackrecord RemoteMessage

  abstract class EndPoint
    getter requested_disconnect : Bool
    getter cmd_buffer : CommandBuffer
    property rpc_connection : CannonInterface?

    def initialize
      super
      @requested_disconnect = false
      @cmd_buffer = CommandBuffer.new
      @io_received = MyMemory.new(1)
      @io_tosend = IO::Memory.new(MAX_PACKAGE_SIZE)
      @remote_acks = CircularAckBuffer(RemoteAckData).new
      @local_acks = CircularAckBuffer(LocalAckData).new
      @remote_message_acks = CircularAckBuffer(RemoteMessage).new
    end

    abstract def on_received_sync
    abstract def before_sending_sync

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

    def command_received
      if it = @rpc_connection
        it.handle_command @io_received
      end
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

      decode_remote_sync
      on_received_sync if most_recent # TODO add size field to skip decoding OoO packets?

      # now process async
      while @io_received.pos < @io_received.size
        id = @io_received.read_bytes(Sequence)
        asize = @io_received.read_bytes(CmdSize)
        if @remote_message_acks.passed(id)
          @io_received.pos += asize
        else
          @remote_message_acks.apply_single id
          command_received
        end
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
      before_sending_sync
      send_local_sync
      # process async
      # TODO - check if too big and split
      @cmd_buffer.select_applicable(MAX_PACKAGE_SIZE - @io_tosend.pos, Time.now) do |cmd|
        @io_tosend.write_bytes(cmd.id)
        @io_tosend.write_bytes(CmdSize.new(cmd.data.size))
        @io_tosend.write(cmd.data.to_slice)
        cur_commands << cmd
        true
      end
      return Bytes.new(@io_tosend.buffer, @io_tosend.pos)
    end
  end
end

macro set_local_sync(typ)
  property local_sync : {{typ}} = {{typ}}.new
  def send_local_sync
    Cannon.encode @io_tosend, @local_sync
  end
end

macro set_remote_sync(typ)
  property remote_sync : {{typ}} = {{typ}}.new
  def decode_remote_sync
    @remote_sync = Cannon.decode @io_received, typeof(@remote_sync)
  end
end
