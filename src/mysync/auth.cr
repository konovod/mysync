require "monocypher"

module MySync
  alias UserID = Int32
  alias UserData = {salt: Crypto::Salt, hash: Crypto::SecretKey, id: UserID}

  abstract class UsersStorage
    abstract def find_user(login : String) : UserData?
    abstract def add_user(login : String, salt : Crypto::Salt, hash : Crypto::SecretKey) : UserData
    abstract def allow_registration(login : String)
  end

  alias Registration = {login: String, salt: Crypto::Salt}
  alias AuthData = (UserData | Registration | Nil)

  abstract class GameServer
    def authorize_1(login : String) : AuthData
      if existing = @users.find_user(login)
        existing
      elsif @users.allow_registration(login)
        {login: login, salt: Crypto::Salt.new}
      else
        nil
      end
    end

    def authorize_2(user : AuthData, hash : Crypto::SecretKey) : EndPoint?
      case user
      when UserData
        if user[:hash].compare(hash)
          return new_endpoint(user[:id])
        else
          return nil
        end
      when Registration
        u = @users.add_user(user[:login], user[:salt], hash)
        return new_endpoint(u[:id])
      else
        return nil
      end
    end

    abstract def new_endpoint(user : UserID) : EndPoint
  end
end
