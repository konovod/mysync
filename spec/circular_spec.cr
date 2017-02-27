require "spec"
require "../src/mysync/circular"

ackrecord TestAck, payload : String

describe "CircularAckBuffer" do
  buf = MySync::CircularAckBuffer(TestAck).new

  ack1 = TestAck.new(false, "ack1")
  ack2 = TestAck.new(false, "ack2")

  it "for uninitialized data passed values are false" do
    buf.passed(12345u16).should be_false
    buf.passed(0u16).should be_false
    buf.passed(65535u16).should be_false
  end

  it "saves consistency when scrolling" do
    buf.cur_seq = 123u16
    buf[122u16] = ack1
    buf[123u16] = ack2
    buf.cur_seq = 124u16
    buf[122u16]?.should eq ack1
    buf[123u16]?.should eq ack2
  end

  it "can mark packets as passed" do
    buf.passed(122u16).should be_false
    buf.set_passed(122u16, true)
    buf.passed(122u16).should be_true
    buf.passed(124u16).should be_false
    buf.set_passed(124u16, true)
    buf.passed(124u16).should be_true

    buf.cur_seq = 125u16
    buf.passed(123u16).should be_false
    buf.passed(124u16).should be_true
  end

  it "old packets become unknown (not passed)" do
    buf.cur_seq = 124u16 + MySync::N_ACKS
    buf[122u16 + MySync::N_ACKS]?.not_nil!.payload.should eq "ack1"
    buf[122u16 + MySync::N_ACKS]?.not_nil!.passed.should be_false
  end

  it "generates mask of passed packets" do
    buf.cur_seq = 500u16
    buf.passed_mask.should eq 0
    buf.set_passed(500u16, true)
    buf.passed_mask.should eq 0
    buf.set_passed(499u16, true)
    buf.passed_mask.should eq 1
    buf.cur_seq = 501u16
    buf.passed_mask.should eq 3
    buf.cur_seq = 502u16
    buf.passed_mask.should eq 6
  end

  it "handles overflows seamlessly" do
    ack3 = TestAck.new(true, "ack3")
    ack4 = TestAck.new(false, "ack4")
    buf.cur_seq = 65534u16
    buf[65533u16] = ack3
    buf[65534u16] = ack4
    buf.cur_seq = 6u16
    buf[65533u16]?.should eq ack3
    buf[65534u16]?.should eq ack4
    buf.passed_mask.should eq (1 << 8)
  end



end
