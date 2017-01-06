

module MySync

  enum Commands
    PING = 1
    TST_SUM = 2
  end


  class Server

    def initialize

    end

    def process_request(io : IO)
      cmd = Commands.new(io.read_bytes(Int32))
      size = io.read_bytes(UInt32)
      return unless cmd && size
      packet = Bytes.new(size)
      io.read_fully(packet)
      case cmd
        when Commands::PING
          process_ping(io, packet)
        when Commands::TST_SUM
          process_sum(io, packet)
      end
    end

    def process_ping(io : IO, packet : Bytes)
      io.write_bytes(packet.size)
      io.write(packet)
    end
    def process_sum(io : IO, packet : Bytes)
      io.write_byte(packet.sum)
    end


  end

  class Client

    def initialize(@io : IO)
    end

    def test_echo(data : Bytes)
      @io.write_bytes(Commands::PING.to_i)
      @io.write_bytes(data.size)
      @io.write(data)
      return false unless @io.read_bytes(Int32) == data.size
      data2 = Bytes.new(data.size)
      @io.read_fully(data2)
      data==data2
    end

    def test_sum(data : Bytes)
      @io.write_bytes(Commands::TST_SUM.to_i)
      @io.write_bytes(data.size)
      @io.write(data)
      return @io.read_byte
    end

  end



end
