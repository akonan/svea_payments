require 'spec_helper'

RSpec.describe SveaPayments::Payment, :type => :request do
  before do
    WebMock.allow_net_connect!
  end
  
  after do
    WebMock.disable_net_connect!(allow_localhost: true)
  end
  describe 'create payment with specific attributes' do
    it 'successfully creates a payment with specific attributes and returns payment ID' do
      
      username = 'ILQXQZEI'
      password = 'Pyq8kd5CFSMSuCxate26xHw73edZyg2ytUQMqJPQ'
      token = SveaPayments::Authentication.get_basic_auth_token(username, password)
      payment_details = {
        'pmt_charsethttp' => 'UTF-8',
        'pmt_charset' => 'UTF-8',
        'pmt_sellerid' => 'ILQXQZEI',
        'pmt_keygeneration' => '001',
        'pmt_id' => rand(20000),
        'pmt_orderid' => '1998524',
        'pmt_reference' => '19985242',
        'pmt_amount' => '568,10',
        'pmt_sellercosts' => '5,00',
        'pmt_currency' => 'EUR',
        'pmt_okreturn' => 'http://www.mytestshop.fi/pay/return/Success.do?paid=1',
        'pmt_errorreturn' => 'http://www.mytestshop.fi/pay/return/Error.do?paid=0',
        'pmt_cancelreturn' => 'http://www.mytestshop.fi/pay/return/Cancel.do?paid=0',
        'pmt_delayedpayreturn' => 'http://www.mytestshop.fi/pay/return/Cancel.do?paid=0',
        'pmt_escrow' => 'N',
        'pmt_escrowchangeallowed' => 'N',
        'pmt_userlocale' => 'en_FI',
        'pmt_buyeremail' => 'teemu.testaaja@svea.fi',
        'pmt_buyerphone' => '0401234567',
        'pmt_buyername' => 'Teemu Testaaja',
        'pmt_buyeraddress' => 'Mechelininkatu 1A',
        'pmt_buyerpostalcode' => '00180',
        'pmt_buyercity' => 'Helsinki',
        'pmt_buyercountry' => 'FI',
        'pmt_deliveryname' => 'Teemu Testaaja',
        'pmt_deliveryaddress' => 'Mechelininkatu 1A',
        'pmt_deliverypostalcode' => '00180',
        'pmt_deliverycity' => 'Helsinki',
        'pmt_deliverycountry' => 'FI',
        'pmt_rows' => '4',
        'pmt_row_name1' => 'Tuote A',
        'pmt_row_desc1' => 'Tuotteen A kuvaus',
        'pmt_row_quantity1' => '2',
        'pmt_row_deliverydate1' => '21.10.2025',
        'pmt_row_price_gross1' => '123,00',
        'pmt_row_vat1' => '24,00',
        'pmt_row_discountpercentage1' => '0,00',
        'pmt_row_type1' => '1',
        'pmt_row_name2' => 'Räätälöity alennustuote B',
        'pmt_row_desc2' => 'Räätälöidyn alennustuotteen kuvaus',
        'pmt_row_quantity2' => '1',
        'pmt_row_deliverydate2' => '21.10.2025',
        'pmt_row_price_gross2' => '369,00',
        'pmt_row_vat2' => '24,00',
        'pmt_row_discountpercentage2' => '10,00',
        'pmt_row_type2' => '4',
        'pmt_row_name3' => 'Toimituskulut',
        'pmt_row_desc3' => 'Toimitustapa yms.',
        'pmt_row_quantity3' => '1',
        'pmt_row_deliverydate3' => '21.10.2025',
        'pmt_row_price_gross3' => '5,00',
        'pmt_row_vat3' => '0,00',
        'pmt_row_discountpercentage3' => '0,00',
        'pmt_row_type3' => '2',
        'pmt_row_name4' => 'Alennus',
        'pmt_row_desc4' => 'Alennuskupongin koodi tms.',
        'pmt_row_quantity4' => '1',
        'pmt_row_deliverydate4' => '21.10.2025',
        'pmt_row_price_gross4' => '-10,00',
        'pmt_row_vat4' => '0,00',
        'pmt_row_discountpercentage4' => '0,00',
        'pmt_row_type4' => '6'
      }

      
      response = SveaPayments::Payment.create_payment(token, payment_details)

      expect(response).to include("pmt_id")
    end
  end
end
