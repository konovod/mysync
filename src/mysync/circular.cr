require "./endpoint_types"

# circular buffer that holds up to N_ACKS values
module MySync
  class CircularAckBuffer(T)
    getter cur_seq : Sequence

    def initialize
      t = uninitialized T
      t = t.set_passed false
      @data = StaticArray(T, N_ACKS).new(t)
      @cur_pos = Sequence.new(0)
      @cur_seq = Sequence.new(0)
    end

    def reset
      @cur_pos = Sequence.new(0)
      @cur_seq = Sequence.new(0)
      t = uninitialized T
      t = t.set_passed false
      N_ACKS.times do |i|
        @data[i] = t
      end
    end

    def cur_seq=(value : Sequence)
      delta = value - @cur_seq
      return if delta == 0
      delta = N_ACKS if delta > N_ACKS
      delta.times do |i|
        index = (@cur_pos - 1 - i + 2*N_ACKS) % N_ACKS
        @data[index] = @data[index].set_passed false
      end
      @cur_pos = (@cur_pos - value + @cur_seq + N_ACKS) % N_ACKS
      @cur_seq = value
    end

    private def seq_to_index(seq : Sequence)
      (@cur_pos + @cur_seq - seq) % N_ACKS
    end

    # private def index_to_seq(index : Int) : Sequence
    #   seq = @cur_seq + @cur_pos - index
    # end

    def apply_single(single : Sequence)
      if SequenceSigned.new(single - @cur_seq) >= 0
        self.cur_seq=(single)
      end
      set_passed(single, true) unless @cur_seq - single > N_ACKS
    end

    def apply_mask(start : Sequence, mask : AckMask)
      return if @cur_seq - start > N_ACKS
      N_ACKS.times do |ir|
        i = (N_ACKS - 1) - ir
        next if (i > 0) && (mask & 1 << (i - 1) == 0)
        seq = start - i
        next if seq <= @cur_seq - N_ACKS
        next if passed(seq)
        set_passed(seq, true)
        yield(@data[seq_to_index(seq)])
      end
    end

    def []?(seq : Sequence) : T?
      return nil if cur_seq - seq > N_ACKS
      # p "#{seq} -> #{seq_to_index(seq)} -> #{index_to_seq(seq_to_index(seq))}"
      @data[seq_to_index(seq)]
    end

    def []=(seq : Sequence, value : T) : Nil
      raise "assigning incorrect seq number #{seq} at current #{cur_seq}" if @cur_seq - seq > N_ACKS
      @data[seq_to_index(seq)] = value
    end

    def passed(seq : Sequence) : Bool
      return false unless value = self[seq]?
      value.passed
    end

    def set_passed(seq : Sequence, value : Bool)
      raise "passing incorrect seq number #{seq} at current #{cur_seq}" if @cur_seq - seq > N_ACKS
      @data[seq_to_index(seq)] = @data[seq_to_index(seq)].set_passed(value)
    end

    def passed_mask : AckMask
      result = 0u32
      (N_ACKS - 1).times do |i|
        result |= 1 << i if @data[(@cur_pos + i + 1) % N_ACKS].passed
      end
      result
    end
  end
end

# TODO - move passed to bitmap
macro ackrecord(name, *properties)
  record {{name}}, passed : Bool, {{*properties}} do
    def set_passed(value : Bool)
      return self if value == self.passed
      @passed = value
      return self
    end
    {{yield}}
  end
end
