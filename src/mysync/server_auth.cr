require "./endpoint"
require "monocypher"
require "socket"
require "./network"
require "./utils/package"
require "./payloads/rpc"

module MySync
  class GameConnection
    private def process_password_packet
      # first it decrypts and check
      debug_str "process_password_packet"
      unless auser = @user
        debug_str "USER DONT MATCH"
        return
      end
      if @received.size - Crypto::OVERHEAD_SYMMETRIC <= 0
        debug_str "SIZE DONT MATCH"
        return
      end
      @received_decrypted.size = @received.size - Crypto::OVERHEAD_SYMMETRIC
      return unless Crypto.decrypt(
                      key: @symmetric_key,
                      input: @received.slice,
                      output: @received_decrypted.slice)
      # check password and create endpoint
      @last_message = @server.time.current
      hash = Crypto::SecretKey.from_bytes(@received_decrypted.slice)
      point = @server.authorize_2(auser, hash)
      unless point
        debug_str "PASS DONT MATCH"
        send_response wrong_pass_response(auser), sign: RIGHT_PASS_SIGN
        return
      end
      @endpoint = point
      # now init common data
      point.rpc_connection = CannonInterface.new point, @server.rpc_manager
      @server.sync_lists.create_specifics point
      # still send positive response, not usual
      # send_response point.process_sending
      send_response Bytes.new(1, 1u8), sign: RIGHT_PASS_SIGN
    end

    private def process_login_packet
      debug_str "process_login_packet"
      # here is encrypted packet with client public key as additional data
      if @received.size < Crypto::PublicKey.size + Crypto::OVERHEAD_SYMMETRIC
        debug_str "size dont match"
        return
      end
      @received_decrypted.size = @received.size - Crypto::OVERHEAD_SYMMETRIC - Crypto::PublicKey.size
      akey = Crypto::PublicKey.from_bytes @received.slice[0, Crypto::PublicKey.size]
      login_key = @server.gen_key(akey)
      return unless Crypto.decrypt(
                      key: login_key,
                      input: @received.slice[Crypto::PublicKey.size, @received.size - Crypto::PublicKey.size],
                      output: @received_decrypted.slice)
      alogin = String.new(@received_decrypted.slice)
      debug_str "decoded login: #{alogin}"
      auser = @server.authorize_1(alogin)
      unless auser
        debug_str "incorrect login"
        send_response wrong_login_response(alogin), key: login_key, sign: RIGHT_LOGIN_SIGN
        return
      end
      @user = auser
      @last_message = @server.time.current
      # successful auth, send symmetric key and salt
      @symmetric_key.reroll
      response = Bytes.new(1 + Crypto::SymmetricKey.size + Crypto::Salt.size)
      response[0] = 1u8
      response[1, Crypto::SymmetricKey.size].copy_from @symmetric_key.to_slice
      response[1 + Crypto::SymmetricKey.size, Crypto::Salt.size].copy_from auser[:salt].to_slice
      send_response response, key: login_key, sign: RIGHT_LOGIN_SIGN
    end

    private def wrong_login_response(alogin)
      Bytes.new(1, 0u8)
    end

    private def wrong_pass_response(auser)
      Bytes.new(1, 0u8)
    end
  end
end
