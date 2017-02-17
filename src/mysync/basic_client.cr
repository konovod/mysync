require "./basic"

module MySync

abstract class Client(ClientSync, ServerSync) < EndPoint(ClientSync, ServerSync)
  abstract def on_connected(user : UserID)

end

end
