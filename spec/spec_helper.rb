# frozen_string_literal: true

require "svea_payments"
require 'webmock/rspec'

WebMock.disable_net_connect!

RSpec.configure do |config|
  # Live specs can create sandbox payments. Never run them implicitly.
  config.filter_run_excluding live: true unless ENV['SVEA_LIVE_TESTS'] == '1'

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
