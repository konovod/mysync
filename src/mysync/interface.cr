require "./endpoint"

module MySync

DISCONNECT_DELAY = Time::Span.new(0,0,1)

abstract class Server(ClientSync, ServerSync)

  def initialize
    @clients = Hash(UserID, UserContext(ClientSync, ServerSync)).new
  end

  #TODO - send packages asynchronously?

  def packet_received(sender : UserID, data : Bytes, answer : Bytes): Int32
    context = @clients[sender]
    if context
      context.last_message = Time.now
      context.package_received.copy_from(data)
      context.process_receive
      result = context.process_sending
      answer.copy_from(context.package_tosend.to_unsafe, result)
      return result
    else
      return 0
    end
  end

  def dump_oldies
    time = Time.now
    @clients.reject! do |id, cli|
      result = cli.requested_disconnect || time - cli.last_message > DISCONNECT_DELAY
      cli.on_disconnect if result
      result
    end
  end

  def do_login(user : UserID) : UserContext(ClientSync, ServerSync)?
    context = on_login(user)
    return nil unless context
    old = @clients[user]?
    old.on_disconnect if old
    @clients[user] = context
    context
  end

  abstract def on_login(user : UserID) : UserContext(ClientSync, ServerSync)?
  # abstract def on_register(user : UserID, data : Bytes) : UserContext(ClientSync, ServerSync)?

end

abstract class UserContext(ClientSync, ServerSync) < EndPoint(ServerSync, ClientSync)
  property last_message : Time
  property requested_disconnect : Bool
  def initialize(@server : Server(ClientSync, ServerSync), @user : UserID)
    super()
    @last_message = Time.now
    @requested_disconnect = false
  end

  abstract def on_disconnect

end


abstract class Client(ClientSync, ServerSync) < EndPoint(ClientSync, ServerSync)
  abstract def on_connected(user : UserID)

end

end
