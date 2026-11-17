require 'spec_helper'
require 'digest'

# Contract: Svea DOCS "Card (tokenization and charging)" (page 1657013059, v13).
# Response bodies follow its examples; tokens and identifiers are placeholders.
RSpec.describe SveaPayments::CardToken do
  let(:secret) { 'test-secret' }
  let(:auth) { 'Basic test-only' }
  let(:token) { '57c48209-0000-0000-0000-000000000000' }
  let(:buyer) do
    { 'pmt_sellerid' => 'seller', 'pmt_id' => 'pay-1', 'pmt_orderid' => 'order-1', 'pmt_reference' => '19985242',
      'pmt_currency' => 'EUR', 'pmt_okreturn' => 'https://shop.test/ok', 'pmt_errorreturn' => 'https://shop.test/error',
      'pmt_cancelreturn' => 'https://shop.test/cancel', 'pmt_delayedpayreturn' => 'https://shop.test/cancel',
      'pmt_escrow' => 'N', 'pmt_escrowchangeallowed' => 'N', 'pmt_buyername' => 'Testi Ostaja' }
  end

  def expected_hash(fields)
    names = SveaPayments::Signature::PAYMENT_REQUEST_FIELDS
    values = names.map { |name| fields[name] }.compact.reject(&:empty?)
    Digest::SHA512.hexdigest((values + [secret]).map { |value| "#{value}&" }.join).upcase
  end

  describe '.registration_form' do
    it 'builds a zero-sum TokenizeExtended form with protocol constants and a valid hash' do
      form = described_class.registration_form(buyer.transform_keys(&:to_sym), secret: secret)
      expect(form['url']).to eq('https://test1.maksuturva.fi/TokenizeExtended.pmt')
      fields = form['fields']
      expect(fields).to include(
        'pmt_action' => 'TOKENIZE', 'pmt_version' => '4504', 'pmt_paymentmethod' => 'FI50',
        'pmt_amount' => '0,00', 'pmt_sellercosts' => '0,00', 'pmt_charset' => 'UTF-8',
        'pmt_charsethttp' => 'UTF-8', 'pmt_hashversion' => 'SHA-512', 'pmt_keygeneration' => '001',
        'pmt_sellerid' => 'seller', 'pmt_id' => 'pay-1'
      )
      expect(fields['pmt_hash']).to eq(expected_hash(fields))
      expect(fields.values).not_to include(secret)
      expect(WebMock).not_to have_requested(:any, /maksuturva/)
    end

    it 'does not let the caller override protocol constants or supply a hash' do
      fields = described_class.registration_form(buyer.merge(
        'pmt_action' => 'NEW_PAYMENT_EXTENDED', 'pmt_version' => '0004', 'pmt_paymentmethod' => 'FI01',
        'pmt_hash' => 'FORGED', 'pmt_hashversion' => 'MD5'
      ), secret: secret)['fields']
      expect(fields).to include('pmt_action' => 'TOKENIZE', 'pmt_version' => '4504', 'pmt_paymentmethod' => 'FI50',
        'pmt_hashversion' => 'SHA-512')
      expect(fields['pmt_hash']).to eq(expected_hash(fields))
    end

    %w[pmt_amount pmt_sellercosts].each do |field|
      it "rejects a non-zero #{field}: registering a card must not charge it" do
        expect { described_class.registration_form(buyer.merge(field => '5,00'), secret: secret) }
          .to raise_error(ArgumentError, /#{field}/)
      end
    end

    it 'rejects a charset other than UTF-8, which the hash is calculated in' do
      expect { described_class.registration_form(buyer.merge('pmt_charset' => 'ISO-8859-1'), secret: secret) }
        .to raise_error(ArgumentError, /pmt_charset/)
    end

    it 'uses the production host and a chosen algorithm and key generation' do
      SveaPayments.configure { |config| config.use_test_env = false }
      form = described_class.registration_form(buyer.merge('pmt_keygeneration' => '002'), secret: secret,
        hash_algorithm: 'SHA-256')
      expect(form['url']).to eq('https://www.maksuturva.fi/TokenizeExtended.pmt')
      expect(form['fields']).to include('pmt_hashversion' => 'SHA-256', 'pmt_keygeneration' => '002')
      expect(form['fields']['pmt_hash'].length).to eq(64)
    ensure
      SveaPayments.configure { |config| config.use_test_env = true }
    end
  end

  describe '.payment_with_registration_form' do
    it 'builds a NewPaymentExtended form with version 4304 and the real amount' do
      form = described_class.payment_with_registration_form(
        buyer.merge('pmt_amount' => '50,00', 'pmt_sellercosts' => '5,00'), secret: secret
      )
      expect(form['url']).to eq('https://test1.maksuturva.fi/NewPaymentExtended.pmt')
      expect(form['fields']).to include('pmt_action' => 'NEW_PAYMENT_EXTENDED', 'pmt_version' => '4304',
        'pmt_paymentmethod' => 'FI50', 'pmt_amount' => '50,00', 'pmt_sellercosts' => '5,00')
      expect(form['fields']['pmt_hash']).to eq(expected_hash(form['fields']))
    end

    [nil, '50.00', 50].each do |amount|
      it "rejects amount #{amount.inspect}" do
        expect { described_class.payment_with_registration_form(buyer.merge('pmt_amount' => amount), secret: secret) }
          .to raise_error(ArgumentError, /pmt_amount/)
      end
    end
  end

  describe '.verify_return' do
    let(:params) do
      fields = { 'pmt_action' => 'TOKENIZE', 'pmt_version' => '4504', 'pmt_id' => 'pay-1',
                 'pmt_reference' => '00000000000019985242', 'pmt_amount' => '0,00', 'pmt_currency' => 'EUR',
                 'pmt_sellercosts' => '0,00', 'pmt_paymentmethod' => 'FI50', 'pmt_escrow' => 'N', 'pmt_token' => token }
      fields.merge('pmt_hash' => Digest::SHA512.hexdigest((fields.values + [secret]).map { |v| "#{v}&" }.join).upcase)
    end

    def verify(input = params, **options)
      described_class.verify_return(input, secret: secret, payment_id: 'pay-1', **options)
    end

    it 'returns the verified fields with the token, ignoring unrelated parameters' do
      result = verify(params.merge('utm_source' => 'x').transform_keys(&:to_sym))
      expect(result).to include('pmt_token' => token, 'pmt_id' => 'pay-1', 'pmt_action' => 'TOKENIZE')
      expect(result).not_to have_key('utm_source')
    end

    it 'accepts a lower-case hash' do
      expect(verify(params.merge('pmt_hash' => params['pmt_hash'].downcase))['pmt_token']).to eq(token)
    end

    %w[pmt_token pmt_id pmt_amount pmt_version pmt_escrow pmt_reference].each do |field|
      it "rejects a return whose #{field} was changed after signing" do
        expect { verify(params.merge(field => 'tampered')) }.to raise_error(SveaPayments::InvalidResponseError)
      end
    end

    it 'rejects a missing or wrong hash, a wrong secret and a wrong algorithm' do
      expect { verify(params.reject { |key, _| key == 'pmt_hash' }) }.to raise_error(SveaPayments::InvalidResponseError, /hash/)
      expect { verify(params.merge('pmt_hash' => 'A' * 128)) }.to raise_error(SveaPayments::InvalidResponseError, /hash/)
      expect { described_class.verify_return(params, secret: 'other', payment_id: 'pay-1') }
        .to raise_error(SveaPayments::InvalidResponseError, /hash/)
      expect { verify(hash_algorithm: 'SHA-256') }.to raise_error(SveaPayments::InvalidResponseError, /hash/)
    end

    it 'rejects a validly signed return for another payment' do
      expect { described_class.verify_return(params, secret: secret, payment_id: 'pay-2') }
        .to raise_error(SveaPayments::InvalidResponseError, /another payment/)
      expect { described_class.verify_return(params, secret: secret, payment_id: nil) }
        .to raise_error(SveaPayments::InvalidResponseError)
    end

    it 'rejects a validly signed return without a token' do
      fields = params.reject { |key, _| %w[pmt_token pmt_hash].include?(key) }
      signed = fields.merge('pmt_hash' => Digest::SHA512.hexdigest((fields.values + [secret]).map { |v| "#{v}&" }.join))
      expect { verify(signed) }.to raise_error(SveaPayments::InvalidResponseError, /no token/)
    end

    it 'rejects array or nested parameter values' do
      expect { verify(params.merge('pmt_token' => [token])) }.to raise_error(SveaPayments::InvalidResponseError)
    end

    it 'never puts the token or secret in an error message' do
      expect { verify(params.merge('pmt_amount' => '1,00')) }.to raise_error { |error|
        expect(error.message).not_to include(token)
        expect(error.message).not_to include(secret)
      }
    end
  end

  describe '.charge' do
    let(:url) { 'https://test1.maksuturva.fi/NewChargeWithTokenExtended.pmt' }
    let(:details) { buyer.merge('pmt_amount' => '50,00', 'pmt_sellercosts' => '5,00', 'pmt_token' => token) }

    def ok_xml(version: '4204', code: '00', extra: '')
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <chargeWithTokenResponse>
            <pmt_action>NEW_PAYMENT_EXTENDED</pmt_action>
            <pmt_version>#{version}</pmt_version>
            <pmt_id>pay-1</pmt_id>
            <pmt_reference>00000000001000002696</pmt_reference>
            <pmt_amount>50,00</pmt_amount>
            <pmt_currency>EUR</pmt_currency>
            <pmt_sellercosts>5,00</pmt_sellercosts>
            <pmt_paymentmethod>FI50</pmt_paymentmethod>
            <pmt_escrow>Y</pmt_escrow>
            <pmt_resultcode>#{code}</pmt_resultcode>
            <pmt_hash>ABCDEF</pmt_hash>
            #{extra}
        </chargeWithTokenResponse>
      XML
    end

    def charge(initiator: :merchant, input: details)
      described_class.charge(auth, input, secret: secret, initiator: initiator)
    end

    { merchant: '4204', customer: '4104' }.each do |initiator, version|
      it "posts a signed #{initiator}-initiated charge as version #{version} and reports it charged" do
        sent = nil
        stub = stub_request(:post, url).with(headers: {
          'Authorization' => auth, 'Content-Type' => 'application/x-www-form-urlencoded'
        }) { |request| sent = URI.decode_www_form(request.body).to_h }.to_return(body: ok_xml(version: version))
        original = details.dup
        result = charge(initiator: initiator)
        expect(sent).to include('pmt_action' => 'NEW_PAYMENT_EXTENDED', 'pmt_version' => version,
          'pmt_paymentmethod' => 'FI50', 'pmt_token' => token, 'pmt_amount' => '50,00', 'pmt_id' => 'pay-1',
          'pmt_hashversion' => 'SHA-512', 'pmt_charset' => 'UTF-8')
        expect(sent['pmt_hash']).to eq(expected_hash(sent))
        expect(sent.values).not_to include(secret)
        expect(result).to include('outcome' => 'charged', 'pmt_resultcode' => '00', 'pmt_id' => 'pay-1',
          'pmt_amount' => '50,00', 'pmt_version' => version, 'errors' => [])
        expect(details).to eq(original)
        expect(stub).to have_been_requested.once
      end
    end

    it 'charges on the separate production host' do
      SveaPayments.configure { |config| config.use_test_env = false }
      stub = stub_request(:post, 'https://payments.maksuturva.fi/NewChargeWithTokenExtended.pmt').to_return(body: ok_xml)
      expect(charge['outcome']).to eq('charged')
      expect(stub).to have_been_requested.once
    ensure
      SveaPayments.configure { |config| config.use_test_env = true }
    end

    [nil, :cit, 'merchant', :recurring].each do |initiator|
      it "requires an explicit initiator, rejecting #{initiator.inspect} before sending" do
        expect { described_class.charge(auth, details, secret: secret, initiator: initiator) }
          .to raise_error(ArgumentError, /initiator/)
        expect(WebMock).not_to have_requested(:post, url)
      end
    end

    it 'rejects missing token, payment ID or amount before sending' do
      %w[pmt_token pmt_id].each do |field|
        expect { charge(input: details.merge(field => ' ')) }.to raise_error(ArgumentError, /#{field}/)
      end
      expect { charge(input: details.merge('pmt_amount' => '50.00')) }.to raise_error(ArgumentError, /pmt_amount/)
      expect(WebMock).not_to have_requested(:post, url)
    end

    it 'reports the customer-initiated soft fail with its authentication URL' do
      stub_request(:post, url).to_return(body: ok_xml(version: '4104', code: '01',
        extra: '<pmt_cardholderauthenticationurl>https://test1.maksuturva.fi/auth/abc</pmt_cardholderauthenticationurl>'))
      expect(charge(initiator: :customer)).to include('outcome' => 'authentication_required',
        'pmt_resultcode' => '01', 'pmt_cardholderauthenticationurl' => 'https://test1.maksuturva.fi/auth/abc')
    end

    ['', '<pmt_cardholderauthenticationurl>http://insecure.test/auth</pmt_cardholderauthenticationurl>',
     '<pmt_cardholderauthenticationurl>javascript:alert(1)</pmt_cardholderauthenticationurl>'].each do |extra|
      it "rejects result 01 without a usable https authentication URL #{extra.inspect}" do
        stub_request(:post, url).to_return(body: ok_xml(code: '01', extra: extra))
        expect { charge(initiator: :customer) }.to raise_error(SveaPayments::InvalidResponseError)
      end
    end

    it 'reports the documented field error reply as failed with structured errors' do
      stub_request(:post, url).to_return(body: <<~XML)
        <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <chargeWithTokenResponse>
          <pmt_resultcode>99</pmt_resultcode>
          <error name="pmt_userlocale" type="field">pmt_userlocale is invalid</error>
        </chargeWithTokenResponse>
      XML
      expect(charge).to include('outcome' => 'failed', 'pmt_resultcode' => '99', 'errors' => [
        { 'type' => 'field', 'name' => 'pmt_userlocale', 'message' => 'pmt_userlocale is invalid' }
      ])
    end

    it 'reports the documented authorization failure reply as failed' do
      stub_request(:post, url).to_return(body: <<~XML)
        <chargeWithTokenResponse>
          <pmt_errorcode>ERROR_CARD_AUTHORIZATION_FAILED</pmt_errorcode>
          <pmt_errortext>Korttitapahtuman varmennus ei onnistunut.</pmt_errortext>
        </chargeWithTokenResponse>
      XML
      expect(charge).to include('outcome' => 'failed', 'pmt_errorcode' => 'ERROR_CARD_AUTHORIZATION_FAILED',
        'pmt_errortext' => 'Korttitapahtuman varmennus ei onnistunut.', 'pmt_resultcode' => nil)
    end

    %w[ERROR_PAYMENT_INSTRUMENT_EXPIRED ERROR_PAYMENT_INSTRUMENT_NOT_FOUND ERROR_PAYMENT_INSTRUMENT_LIMIT_EXCEEDED
       EXTERNAL_SERVICE_DENIED ERROR].each do |error_code|
      it "reports #{error_code} as failed" do
        stub_request(:post, url).to_return(body: "<chargeWithTokenResponse><pmt_errorcode>#{error_code}</pmt_errorcode></chargeWithTokenResponse>")
        expect(charge['outcome']).to eq('failed')
      end
    end

    %w[ERROR_CARD_AUTHORIZATION_TIMEOUT WAITING ALREADY_PAID].each do |error_code|
      it "reports #{error_code} as unknown, to be reconciled by a status query" do
        stub = stub_request(:post, url).to_return(body: "<chargeWithTokenResponse><pmt_resultcode>99</pmt_resultcode><pmt_errorcode>#{error_code}</pmt_errorcode></chargeWithTokenResponse>")
        expect(charge['outcome']).to eq('unknown')
        expect(stub).to have_been_requested.once
      end
    end

    it 'does not treat an undocumented result code as charged or refused' do
      stub_request(:post, url).to_return(body: ok_xml(code: '42'))
      expect(charge['outcome']).to eq('unknown')
    end

    it 'rejects a success reply for another payment' do
      stub_request(:post, url).to_return(body: ok_xml.sub('>pay-1<', '>pay-2<'))
      expect { charge }.to raise_error(SveaPayments::InvalidResponseError)
    end

    it 'rejects a success reply without a payment ID' do
      stub_request(:post, url).to_return(body: ok_xml.sub(%r{<pmt_id>.*?</pmt_id>}, ''))
      expect { charge }.to raise_error(SveaPayments::InvalidResponseError)
    end

    it 'rejects a reply reporting both success and an error code' do
      stub_request(:post, url).to_return(body: ok_xml(extra: '<pmt_errorcode>ERROR</pmt_errorcode>'))
      expect { charge }.to raise_error(SveaPayments::InvalidResponseError)
    end

    ['', '<html/>', '<broken>', '<pmt><pmt_resultcode>00</pmt_resultcode></pmt>', '<chargeWithTokenResponse/>',
     '<chargeWithTokenResponse><pmt_resultcode>0</pmt_resultcode></chargeWithTokenResponse>',
     '<chargeWithTokenResponse><pmt_resultcode>00</pmt_resultcode><pmt_resultcode>99</pmt_resultcode></chargeWithTokenResponse>'].each do |body|
      it "rejects an unusable reply #{body.inspect} as an unknown outcome" do
        stub_request(:post, url).to_return(body: body)
        expect { charge }.to raise_error(SveaPayments::InvalidResponseError)
      end
    end

    [401, 500, 503].each do |status|
      it "raises an HTTP error for #{status} even with a successful-looking body, without retrying" do
        stub = stub_request(:post, url).to_return(status: status, body: ok_xml)
        expect { charge }.to raise_error(SveaPayments::HTTPError) { |error| expect(error.status).to eq(status) }
        expect(stub).to have_been_requested.once
      end
    end

    it 'propagates a timeout without retrying a charge' do
      stub = stub_request(:post, url).to_timeout
      expect { charge }.to raise_error(Timeout::Error)
      expect(stub).to have_been_requested.once
    end

    it 'never puts the token or secret in a raised message' do
      stub_request(:post, url).to_return(body: ok_xml.sub('>pay-1<', '>pay-2<'))
      expect { charge }.to raise_error { |error|
        expect(error.message).not_to include(token)
        expect(error.message).not_to include(secret)
      }
    end
  end

  it 'returns token and card fields from a payment status query, as in the documented example' do
    stub_request(:post, 'https://test1.maksuturva.fi/PaymentStatusQuery.pmt').to_return(body: <<~XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <pmtq>
        <pmtq_action>PAYMENT_STATUS_QUERY</pmtq_action>
        <pmtq_amount>568,10</pmtq_amount>
        <pmtq_card_funding_type>DEBIT</pmtq_card_funding_type>
        <pmtq_card_number_masked>0024</pmtq_card_number_masked>
        <pmtq_card_scheme>VISA</pmtq_card_scheme>
        <pmtq_hash>***</pmtq_hash>
        <pmtq_id>1234567</pmtq_id>
        <pmtq_paymentmethod>FI50</pmtq_paymentmethod>
        <pmtq_returncode>40</pmtq_returncode>
        <pmtq_returntext>Compensated to the seller</pmtq_returntext>
        <pmtq_sellerid>seller</pmtq_sellerid>
        <pmtq_token>#{token}</pmtq_token>
        <pmtq_token_authentication_required>N</pmtq_token_authentication_required>
        <pmtq_token_debit_limit>1203,51</pmtq_token_debit_limit>
        <pmtq_token_expiration_month>11</pmtq_token_expiration_month>
        <pmtq_token_expiration_year>2017</pmtq_token_expiration_year>
        <pmtq_version>0005</pmtq_version>
      </pmtq>
    XML
    expect(SveaPayments::Payment.query_payment_status(auth, '1234567', 'seller')).to include(
      'pmtq_returncode' => '40', 'pmtq_token' => token, 'pmtq_token_authentication_required' => 'N',
      'pmtq_token_debit_limit' => '1203,51', 'pmtq_token_expiration_month' => '11',
      'pmtq_token_expiration_year' => '2017', 'pmtq_card_number_masked' => '0024', 'pmtq_card_scheme' => 'VISA',
      'pmtq_card_funding_type' => 'DEBIT'
    )
  end
end
