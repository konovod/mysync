require "cannon/rpc"
require "../circular"
require "../endpoint_types"

module MySync
  abstract class EndPoint
    property! rpc_connection : CannonInterface
    ackrecord RemoteMessage
    # TODO - it's still used in reset
    @remote_message_acks = CircularAckBuffer(RemoteMessage).new

    def command_received
      if it = @rpc_connection
        it.handle_command @io_received
      end
    end

    def receive_asyncs
      while @io_received.pos < @io_received.size
        id = @io_received.read_bytes(Sequence)
        break if id == 0
        asize = @io_received.read_bytes(CmdSize)
        if @remote_message_acks.passed(id)
          @io_received.pos += asize
        else
          @remote_message_acks.apply_single id
          command_received
        end
      end
    end

    def send_asyncs(cur_commands)
      @cmd_buffer.select_applicable(MAX_PACKAGE_SIZE - sizeof(CmdID) - @io_tosend.pos, Time.now) do |cmd|
        @io_tosend.write_bytes(cmd.id)
        @io_tosend.write_bytes(CmdSize.new(cmd.data.size))
        @io_tosend.write(cmd.data.to_slice)
        cur_commands << cmd
        true
      end
      @io_tosend.write_bytes(CmdID.new(0))
    end
  end

  # TODO - later optimize to single buffer
  # record Command, offset : Int32, size : Int32
  RESEND_TIME = (0.2).seconds
  alias CmdSize = UInt8
  alias CmdID = Sequence

  class Command
    getter data
    property sent : Time
    getter id

    def initialize(@id : CmdID, @data : Bytes)
      @sent = Time.now - RESEND_TIME*2
    end
  end

  class CommandBuffer
    def initialize
      @commands = Array(Command).new
      @last_sent_id = CmdID.new(0)
    end

    def add(data : Bytes) : Nil
      @last_sent_id += 1
      @last_sent_id += 1 if @last_sent_id == 0
      cmd = Command.new(@last_sent_id, data)
      @commands << cmd
    end

    def acked(cmd)
      @commands.delete cmd
    end

    def select_applicable(remaining_size : Int32, time : Time, &block)
      # TODO - slicing big commands?
      @commands.each do |cmd|
        next if cmd.data.size > remaining_size
        next if time - cmd.sent < RESEND_TIME
        ok = yield(cmd)
        if ok
          remaining_size -= cmd.data.size
          cmd.sent = time
        end
      end
    end
  end
end
