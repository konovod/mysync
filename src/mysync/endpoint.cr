require "cannon"
require "./endpoint_types"
require "./circular"
require "./stats"
require "./payloads/commands"
require "./payloads/rpc"
require "./payloads/lists"

module MySync
  module EndPointFactory
    getter rpc_manager = Cannon::Rpc::Manager.new
    getter sync_lists = SyncListsManager.new

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
  ackrecord RemoteAckData
  ackrecord LocalAckData, sent : Time = Time.new, commands = [] of Command

  abstract class EndPoint
    getter requested_disconnect : Bool
    getter cmd_buffer = CommandBuffer.new
    getter sync_lists_serverside
    property! sync_lists : SyncListsManager

    def initialize
      super
      @requested_disconnect = false
      @io_received = MyMemory.new(1)
      @io_tosend = IO::Memory.new(MAX_PACKAGE_SIZE)
      @remote_acks = CircularAckBuffer(RemoteAckData).new
      @local_acks = CircularAckBuffer(LocalAckData).new
      @sync_lists_serverside = Hash(ServerSyncList, SyncListEndpointSpecific).new
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

      decode_remote_sync # TODO add size field to skip decoding OoO packets?

      # now process async
      receive_asyncs
      # now process syncronized lists
      if most_recent
        sync_lists.process_received(@io_received)
        # and finally call callback
        on_received_sync
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
      # TODO - check if too big and split
      send_asyncs(cur_commands)
      # process syncronized lists
      sync_lists.generate_message(self, @io_tosend)
      return @io_tosend.to_slice
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
