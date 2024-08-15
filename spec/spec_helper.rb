# frozen_string_literal: true

require "svea_payments"
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  Dir[File.join(__dir__, 'spec/**/*.rb')].each { |f| require f }

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"
  

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  SveaPayments.configure do |config|
    config.use_test_env = true
  end
end
