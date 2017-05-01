require "monocypher"

module MySync
  alias UserID = Int32
  alias UserData = {salt: Crypto::Salt, hash: Crypto::SecretKey, id: UserID}

  abstract class UsersStorage
    abstract def find_user(login : String) : UserData?
    abstract def add_user(login : String, salt : Crypto::Salt, hash : Crypto::SecretKey)
  end

  abstract class GameServer
    def authorize_1(login : String) : Crypto::Salt?
      @users.find_user(login).try { |value| value[:salt] }
    end

    def authorize_2(login : String, hash : Crypto::SecretKey) : EndPoint?
      # TODO - auto adding
      return nil unless data = @users.find_user(login)
      return nil unless data[:hash].compare(hash)
      return new_endpoint(data[:id])
    end

    abstract def new_endpoint(user : UserID) : EndPoint
  end
end
