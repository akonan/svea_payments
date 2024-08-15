require_relative "svea_payments/version"
require_relative "svea_payments/authentication"
require_relative "svea_payments/payment"

module SveaPayments
  BASE_URL_TEST = "https://test1.maksuturva.fi"
  BASE_URL_PROD = "https://www.maksuturva.fi"

  class Error < StandardError; end

  module Configuration
    @use_test_env = false

    class << self
      attr_accessor :use_test_env
    end
  end

  def self.configure
    yield(Configuration)
  end

  def self.base_url
    Configuration.use_test_env ? BASE_URL_TEST : BASE_URL_PROD
  end
end