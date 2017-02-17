require "./basic"

module MySync

abstract class Server(ClientSync, ServerSync)

  def initialize
    #@logins = Hash.new(String, ClientID).new()
    #@clients = Hash(ClientID, ClientData).new()
  end

  abstract def on_login(user : UserID) : UserContext(ClientSync, ServerSync)?
  abstract def on_register(user : UserID) : UserContext(ClientSync, ServerSync)?

end

abstract class UserContext(ClientSync, ServerSync) < EndPoint(ServerSync, ClientSync)

  def initialize(@server : Server(ClientSync, ServerSync), @user : UserID)
    super()
  end

  abstract def on_disconnect

end



end
