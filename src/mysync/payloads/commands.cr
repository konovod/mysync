require "../endpoint_types"

module MySync
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
