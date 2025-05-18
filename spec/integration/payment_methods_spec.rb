require 'spec_helper'

RSpec.describe SveaPayments::PaymentMethods, :type => :request do
  before do
    WebMock.allow_net_connect!
  end

  after do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  describe 'get available payment methods' do
    it 'successfully retrieves available payment methods' do
      username = 'ILQXQZEI'
      password = 'Pyq8kd5CFSMSuCxate26xHw73edZyg2ytUQMqJPQ'
      token = SveaPayments::Authentication.get_basic_auth_token(username, password)

      request_details = {
        'sellerid' => 'ILQXQZEI',
        'request_locale' => 'fi',
        'totalamount' => '47,50'
      }

      expected_result = [
        {
          code: "FI01",
          displayname: "Nordea E-maksu",
          imageurl: {
            url: "https://www.maksuturva.fi/public_img/paymentmethods/FI01_fi.png",
            width: 150,
            height: 80,
            mimetype: "image/png"
          }
        },
        {
          code: "FI02",
          displayname: "Danske Bank Verkkomaksu",
          imageurl: {
            url: "https://www.maksuturva.fi/public_img/paymentmethods/FI02_fi.png",
            width: 80,
            height: 80,
            mimetype: "image/png"
          }
        },
        {
          code: "FI03",
          displayname: "Aktia verkkomaksu",
          imageurl: {
            url: "https://www.maksuturva.fi/public_img/paymentmethods/FI03_fi.png",
            width: 80,
            height: 80,
            mimetype: "image/png"
          }
        },
        {
          code: "FI04",
          displayname: "POP Pankin verkkomaksu",
          imageurl: {
            url: "https://www.maksuturva.fi/public_img/paymentmethods/FI04_fi.png",
            width: 80,
            height: 80,
            mimetype: "image/png"
          }
        },
        {
          code: "FI06",
          displayname: "Osuuspankki Verkkomaksu",
          imageurl: {
            url: "https://www.maksuturva.fi/public_img/paymentmethods/FI06_fi.png",
            width: 80,
            height: 80,
            mimetype: "image/png"
          }
        },
        {
          code: "FI07",
          displayname: "Ålandsbanken E-maksu",
          imageurl: {
            url: "https://www.maksuturva.fi/public_img/paymentmethods/FI07_fi.png",
            width: 150,
            height: 80,
            mimetype: "image/png"
          }
        },
        {
          code: "FI08",
          displayname: "Säästöpankin verkkomaksu",
          imageurl: {
            url: "https://www.maksuturva.fi/public_img/paymentmethods/FI08_fi.png",
            width: 80,
            height: 80,
            mimetype: "image/png"
          }
        },
        {
          code: "FI10",
          displayname: "S-pankki Verkkomaksu",
          imageurl: {
            url: "https://www.maksuturva.fi/public_img/paymentmethods/FI10_fi.png",
            width: 80,
            height: 80,
            mimetype: "image/png"
          }
        },
        {
          code: "FI11",
          displayname: "Oma Säästöpankin verkkomaksu",
          imageurl: {
            url: "https://www.maksuturva.fi/public_img/paymentmethods/FI11_fi.png",
            width: 80,
            height: 80,
            mimetype: "image/png"
          }
        },
        {
          code: "FI70",
          displayname: "Svea Lasku",
          imageurl: {
            url: "https://www.maksuturva.fi/public_img/paymentmethods/FI70_fi.png",
            width: 80,
            height: 80,
            mimetype: "image/png"
          }
        },
        {
          code: "FI72",
          displayname: "Svea Yrityslasku",
          imageurl: {
            url: "https://www.maksuturva.fi/public_img/paymentmethods/FI72_fi.png",
            width: 150,
            height: 80,
            mimetype: "image/png"
          }
        }
      ]

      response = SveaPayments::PaymentMethods.get_available_payment_methods(token, request_details)
      # Verify response structure
      expect(response).to match_array(expected_result)
    end

    it 'handles missing required parameters' do
      username = 'ILQXQZEI'
      password = 'Pyq8kd5CFSMSuCxate26xHw73edZyg2ytUQMqJPQ'
      token = SveaPayments::Authentication.get_basic_auth_token(username, password)

      # Missing required parameters
      request_details = {
        'sellerid' => 'ILQXQZEI',
        # Deliberately omitting amount and currency
        'request_locale' => 'fi'
      }

      response = SveaPayments::PaymentMethods.get_available_payment_methods(token, request_details)
      expect(response.count).to eq(12)
    end

  end
end
