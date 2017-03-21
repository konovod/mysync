module MySync
  # must be unsigned for seamless overflow
  alias Sequence = UInt16
  alias SequenceSigned = Int16

  alias AckMask = UInt32
  N_ACKS = 32 + 1
end
