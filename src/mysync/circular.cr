require "./endpoint"

# circular buffer that holds up to N_ACKS values
module MySync
  class CircularAckBuffer(T)
    getter cur_seq : Sequence

    def initialize
      @data = uninitialized StaticArray(T, N_ACKS)
      N_ACKS.times do |i|
        @data[i].passed = false
      end
      @cur_pos = Sequence.new(0)
      @cur_seq = Sequence.new(0)
    end

    def cur_seq=(value : Sequence)
      @cur_pos = (@cur_pos - value + @cur_seq) % N_ACKS
      @cur_seq = value
    end

    private def seq_to_index(seq : Sequence)
      (@cur_pos + @cur_seq - seq) % N_ACKS
    end

    def []?(seq : Sequence) : T?
      return nil if cur_seq - seq > N_ACKS
      @data[seq_to_index(seq)]
    end

    def []=(seq : Sequence, value : T) : Nil
      raise "incorrect seq number" if cur_seq - seq > N_ACKS
      @data[seq_to_index(seq)] = value
    end

    def passed(seq : Sequence) : Bool
      return false unless value = self[seq]?
      value.passed
    end

    def set_passed(seq : Sequence, value : Bool)
      return if seq - cur_seq > N_ACKS
      @data[seq_to_index(seq)].passed = value
    end
  end
end

macro ackrecord(name, *properties)
  record {{name}}, passed : Bool, {{*properties}} do
    def passed=(value : Bool)
      @passed = value
    end
    {{yield}}
  end
end
