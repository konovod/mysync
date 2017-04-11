require "cannon/rpc"
require "../circular"
require "../endpoint_types"

module MySync
  module EndPointFactory
    getter rpc_manager = Cannon::Rpc::Manager.new
  end

  abstract class EndPoint
    ackrecord RemoteMessage

    property! rpc_connection : CannonInterface
    getter cmd_buffer = CommandBuffer.new
    # TODO - it's still used in reset
    @remote_message_acks = CircularAckBuffer(RemoteMessage).new

    def command_received
      if it = @rpc_connection
        it.handle_command @io_received
      end
    end

    def acked_asyncs(data : LocalAckData)
      data.commands.each { |cmd| @cmd_buffer.acked cmd }
    end

    def receive_asyncs(io)
      while io.pos < io.size
        id = io.read_bytes(Sequence)
        break if id == 0
        asize = io.read_bytes(CmdSize)
        if @remote_message_acks.passed(id)
          io.pos += asize
        else
          @remote_message_acks.apply_single id
          command_received
        end
      end
    end

    def send_asyncs(io, cur_commands)
      @cmd_buffer.select_applicable(MAX_PACKAGE_SIZE - sizeof(CmdID) - io.pos, Time.now) do |cmd|
        io.write_bytes(cmd.id)
        io.write_bytes(CmdSize.new(cmd.data.size))
        io.write(cmd.data.to_slice)
        cur_commands << cmd
        true
      end
      io.write_bytes(CmdID.new(0))
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
