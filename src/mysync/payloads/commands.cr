require "cannon/rpc"
require "../circular"
require "../endpoint_types"

module MySync
  abstract class GameServer
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

    # returns first command and its data size
    def send_asyncs(io, cur_commands)
      # TODO - slicing big commands?
      first = {nil, 0}
      time = Time.now
      @cmd_buffer.each_applicable(time) do |cmd|
        io.write_bytes(cmd.id)
        io.write_bytes(CmdSize.new(cmd.data.size))
        io.write(cmd.data.to_slice)
        first = {cmd, io.pos} unless first[0]
        cur_commands << cmd
      end
      io.write_bytes(CmdID.new(0))
      return first
    end

    def limit_asyncs(io, cur_commands, size)
      # reset io to position after first command and add terminator
      io.pos = size
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

    def each_applicable(time : Time, &block)
      @commands.each do |cmd|
        yield(cmd) if time - cmd.sent >= RESEND_TIME
      end
    end
  end
end
