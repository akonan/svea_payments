require_relative 'base'
require 'base64'

module SveaPayments
  class Authentication
    extend Base
    def self.get_basic_auth_token(username, password)
      base64_user_pass = Base64.strict_encode64("#{username}:#{password}")
      uri = URI("#{SveaPayments.base_url}/NewPaymentExtended.pmt")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Basic #{base64_user_pass}"
    end
  end
end
