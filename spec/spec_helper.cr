require "spec"
require "cannon"
require "../src/mysync"
require "../src/mysync/server"
require "../src/mysync/serialization"
require "../src/mysync/endpoint"
require "../src/mysync/client"

class SpecLogger
  @@events = [] of String

  def self.log_srv(s : String)
    @@events << "SERVER: #{s}"
  end

  def self.log_cli(s : String)
    @@events << "CLIENT: #{s}"
  end

  def self.dump_events
    r = @@events.clone
    @@events.clear
    r
  end
end

struct TestClientInput
  include Cannon::Auto
  property num : Int32
  property data : String

  def initialize
    @num = -1
    @data = ""
  end

  def initialize(@num, @data)
  end
end

struct TestServerOutput
  include Cannon::Auto
  property all_data

  def initialize
    @all_data = StaticArray(String, 16).new("")
  end

  def initialize(@all_data)
  end
end

# compiler bug?
# ####hopefully fixed in 0.21.0
######################
macro solve_bug

  def process_receive(data)
    super
  end

  def process_sending
    super
  end

  def local_seq=(value)
    super
  end

  def remote_seq=(value)
    super
  end

  def local_seq
    super
  end

  def remote_seq
    super
  end

end
