require "cannon"

struct StaticArray(T, N)
  def to_cannon_io(io)
    if ::Cannon.simple?({{ T }})
      me = self
      io.write pointerof(me).as(UInt8*).to_slice(N * sizeof(T))
    else
      N.times do |index|
        ::Cannon.encode(io, self[index])
      end
    end
    io
  end

  def self.from_cannon_io(io)
    ary = uninitialized self
    if ::Cannon.simple?({{ T }})
      io.read_fully ary.to_unsafe.as(UInt8*).to_slice(N * sizeof(T))
    else
      N.times do |index|
        ary[index] = ::Cannon.decode(io, T)
      end
    end
    ary
  end
end
