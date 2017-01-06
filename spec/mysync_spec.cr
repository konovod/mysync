require "./spec_helper"

describe MySync do

  srv = MySync::Server.new
   
  it "test sum" do
    virtual_server(srv) do |cli|
      data = StaticArray[1u8,2u8,3u8,4u8]
      cli.test_sum(data.to_slice).should eq (data.sum)
    end
  end
  it "test echo" do
    virtual_server(srv) do |cli|
      data = StaticArray[1u8,2u8,3u8,4u8]
      cli.test_echo(data.to_slice).should eq true
    end
  end

end
