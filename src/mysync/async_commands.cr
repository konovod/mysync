module MySync
  # TODO - later optimize to single buffer
  # record Command, offset : Int32, size : Int32
  RESEND_TIME = (0.2).seconds

  class Command
    getter data
    property sent : Time
    getter id

    def need_answer : Bool
      @complete_channel
    end

    def initialize(@id : Int32, @data : Bytes, @complete_channel : ReceiveChannel?)
      @sent = Time.now - 1.seconds
    end
  end

  class CommandBuffer
    def initialize
      @commands = Array(Command).new
      @last_sent_id = 0
    end

    def add(cmd) : Nil
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
