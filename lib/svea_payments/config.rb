module SveaPayments
  module Config
    def base_url
      if SveaPayments.configuration.use_test_env
        "https://test1.maksuturva.fi"
      else
        "https://www.maksuturva.fi"
      end
    end
  end
end