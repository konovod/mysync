require "./spec_helper"


class ClientStaticSpec < MySync::Client
  setter to_send : Int32 = 0
  getter was_recvd : Int32 = 0
  setter recv_count : Int32 = 1
  setter send_count : Int32 = 1
  def send_static
    @send_count.times do
      @io.write_bytes(@to_send)
    end
  end
  def recv_static
    @was_recvd = 0
    @recv_count.times do
      @was_recvd += @io.read_bytes(Int32)
    end
  end
end

class ServerStaticSpec < MySync::Server
  setter to_send : Int32 = 0
  getter was_recvd : Int32 = 0
  setter recv_count : Int32 = 1
  setter send_count : Int32 = 1
  def send_static(io : IO)
    @send_count.times do
      io.write_bytes(@to_send)
    end
  end
  def recv_static(io : IO)
    @was_recvd = 0
    @recv_count.times do
      @was_recvd += io.read_bytes(Int32)
    end
  end
end


describe ClientStaticSpec do

  srv = ServerStaticSpec.new()
  cli = ClientStaticSpec.new(virtual_connect(srv))

  it "test send" do
     cli.to_send = 123
     cli.do_link
     srv.was_recvd.should eq 123
  end
  it "test recv" do
     srv.to_send = 456
     cli.do_link
     cli.was_recvd.should eq 456
  end
  it "test sizes" do
     cli.send_count = 2
     srv.recv_count = 2
     srv.send_count = 3
     cli.recv_count = 3
     cli.do_link
     srv.was_recvd.should eq 123*2
     cli.was_recvd.should eq 456*3
  end
  pending "test wrong sizes" do
     cli.send_count = 2
     srv.recv_count = 3
     srv.send_count = 2
     cli.recv_count = 3
     expect_raises() do
       cli.do_link
     end
  end


end
