require_relative 'base'
require 'base64'

module SveaPayments
  class Authentication
    extend Base
    def self.get_basic_auth_token(username, password)
      base64_user_pass = Base64.strict_encode64("#{username}:#{password}")
      "Basic #{base64_user_pass}"
    end
  end
end
