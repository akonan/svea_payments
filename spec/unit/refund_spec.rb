require 'spec_helper'

RSpec.describe 'After-settlement refunds' do
  let(:url) { 'https://test1.maksuturva.fi/PaymentCancel.pmt' }
  let(:token) { 'Basic test-only' }
  let(:details) do
    { 'pmtc_sellerid' => 'seller', 'pmtc_id' => 'order-123',
      'pmtc_amount' => '100,00', 'pmtc_currency' => 'EUR',
      'pmtc_cancelamount' => '15,00', 'pmtc_cancel_id' => 'refund-123' }
  end

  def response_xml(code = '00', extra = nil)
    extra ||= code == '00' ? <<~XML : ''
      <pmtc_pay_with_reference>00000666660000010007</pmtc_pay_with_reference>
      <pmtc_pay_with_recipientname>Svea Payments Oy</pmtc_pay_with_recipientname>
      <pmtc_pay_with_amount>15,00</pmtc_pay_with_amount>
      <pmtc_pay_with_iban>FI7740123477777777</pmtc_pay_with_iban>
    XML
    <<~XML
      <pmtc>
        <pmtc_action>REFUND_AFTER_SETTLEMENT</pmtc_action>
        <pmtc_version>0005</pmtc_version>
        <pmtc_sellerid>seller</pmtc_sellerid><pmtc_id>order-123</pmtc_id>
        <pmtc_returncode>#{code}</pmtc_returncode>
        <pmtc_returntext>Provider text</pmtc_returntext>
        #{extra}
      </pmtc>
    XML
  end

  it 'posts authenticated form data and preserves all funding instructions as strings' do
    expected = details.merge(
      'pmtc_action' => 'REFUND_AFTER_SETTLEMENT', 'pmtc_version' => '0005',
      'pmtc_canceltype' => 'REFUND_AFTER_SETTLEMENT',
      'pmtc_resptype' => 'XML', 'pmtc_keygeneration' => '001'
    )
    stub = stub_request(:post, url).with(body: expected, headers: {
      'Authorization' => token, 'Content-Type' => 'application/x-www-form-urlencoded'
    }).to_return(body: response_xml('00', <<~XML))
      <pmtc_pay_with_reference>00000666660000010007</pmtc_pay_with_reference>
      <pmtc_pay_with_recipientname>Svea Payments Oy</pmtc_pay_with_recipientname>
      <pmtc_pay_with_amount>15,00</pmtc_pay_with_amount>
      <pmtc_pay_with_iban>FI7740123477777777</pmtc_pay_with_iban>
    XML
    original = details.dup
    result = SveaPayments::Payment.refund_after_settlement(token, details)
    expect(result).to include('pmtc_returncode' => '00',
      'pmtc_pay_with_reference' => '00000666660000010007',
      'pmtc_pay_with_recipientname' => 'Svea Payments Oy',
      'pmtc_pay_with_amount' => '15,00', 'pmtc_pay_with_iban' => 'FI7740123477777777',
      'errors' => [])
    expect(details).to eq(original)
    expect(stub).to have_been_requested.once
  end

  %w[20 90 91 99 42].each do |code|
    it "preserves business response #{code} without retrying or inventing its meaning" do
      stub = stub_request(:post, url).to_return(body: response_xml(code,
        '<errors><error type="field" name="pmtc_id">Invalid ID</error><error type="general">Other error</error></errors>'))
      result = SveaPayments::Payment.refund_after_settlement(token, details)
      expect(result['pmtc_returncode']).to eq(code)
      expect(result['pmtc_returntext']).to eq('Provider text')
      expect(result['errors']).to eq([
        { 'type' => 'field', 'name' => 'pmtc_id', 'message' => 'Invalid ID' },
        { 'type' => 'general', 'name' => nil, 'message' => 'Other error' }
      ])
      expect(stub).to have_been_requested.once
    end
  end

  it 'supports full refunds, optional fields, symbol keys and a custom key generation' do
    input = details.merge('pmtc_cancelamount' => '100,00', 'pmtc_keygeneration' => '002',
      'pmtc_cancelreason' => 'OTHER', 'pmtc_canceldescription' => 'Väärä tuote & koko',
      'pmtc_payeribanrefund' => 'FI7740123477777777', 'pmtc_pay_with_reference' => '12344',
      'pmtc_action' => 'WRONG', 'pmtc_version' => 'WRONG',
      'pmtc_canceltype' => 'WRONG', 'pmtc_resptype' => 'WRONG')
    stub_request(:post, url).with(body: hash_including(input.merge(
      'pmtc_action' => 'REFUND_AFTER_SETTLEMENT', 'pmtc_version' => '0005',
      'pmtc_canceltype' => 'REFUND_AFTER_SETTLEMENT', 'pmtc_resptype' => 'XML'
    ))).to_return(body: response_xml)
    SveaPayments::Payment.refund_after_settlement(token, input.transform_keys(&:to_sym))
  end

  it 'allows the documented optional refund ID to be omitted' do
    stub_request(:post, url).with { |req| !URI.decode_www_form(req.body).to_h.key?('pmtc_cancel_id') }
      .to_return(body: response_xml)
    SveaPayments::Payment.refund_after_settlement(token, details.reject { |k, _| k == 'pmtc_cancel_id' })
  end

  it 'selects the production endpoint without allowing an actual network connection' do
    begin
      SveaPayments.configuration.use_test_env = false
      stub = stub_request(:post, 'https://www.maksuturva.fi/PaymentCancel.pmt').to_return(body: response_xml)
      SveaPayments::Payment.refund_after_settlement(token, details)
      expect(stub).to have_been_requested.once
    ensure
      SveaPayments.configuration.use_test_env = true
    end
  end

  %w[pmtc_sellerid pmtc_id pmtc_amount pmtc_currency pmtc_cancelamount].each do |field|
    it "rejects missing #{field} before sending" do
      expect { SveaPayments::Payment.refund_after_settlement(token, details.reject { |k, _| k == field }) }
        .to raise_error(ArgumentError, /#{field}/)
    end
  end

  ['15.00', '1 000,00', '15,0', 15.0].each do |amount|
    it "rejects ambiguous amount #{amount.inspect}" do
      expect { SveaPayments::Payment.refund_after_settlement(token, details.merge('pmtc_cancelamount' => amount)) }
        .to raise_error(ArgumentError, /pmtc_cancelamount/)
    end
  end

  [401, 500, 302].each do |status|
    it "raises an HTTP error for #{status} rather than reporting business success" do
      stub = stub_request(:post, url).to_return(status: status, body: response_xml)
      expect { SveaPayments::Payment.refund_after_settlement(token, details) }
        .to raise_error(SveaPayments::HTTPError) { |e| expect(e.status).to eq(status) }
      expect(stub).to have_been_requested.once
    end
  end

  ['', '<pmtc>', '<html/>', '<pmtc/>'].each do |body|
    it "rejects an invalid response #{body.inspect}" do
      stub_request(:post, url).to_return(body: body)
      expect { SveaPayments::Payment.refund_after_settlement(token, details) }
        .to raise_error(SveaPayments::InvalidResponseError)
    end
  end

  it 'propagates a timeout without retrying a financial operation' do
    stub = stub_request(:post, url).to_timeout
    expect { SveaPayments::Payment.refund_after_settlement(token, details) }.to raise_error(Timeout::Error)
    expect(stub).to have_been_requested.once
  end

  %w[pmtc_action pmtc_version pmtc_sellerid pmtc_id].each do |field|
    %w[missing mismatched].each do |kind|
      %w[00 90].each do |code|
        it "rejects #{kind} #{field} for response #{code} without retry" do
          body = response_xml(code).sub(/<#{field}>.*?<\/#{field}>/,
            kind == 'missing' ? '' : "<#{field}>wrong</#{field}>")
          stub = stub_request(:post, url).to_return(body: body)
          expect { SveaPayments::Payment.refund_after_settlement(token, details) }
            .to raise_error(SveaPayments::InvalidResponseError, /#{field}.*outcome may be unknown/)
          expect(stub).to have_been_requested.once
        end
      end
    end
  end

  %w[pmtc_pay_with_reference pmtc_pay_with_recipientname pmtc_pay_with_amount pmtc_pay_with_iban].each do |field|
    ['', "<FIELD/>", '<FIELD>   </FIELD>'].each do |replacement|
      it "rejects missing or blank funding field #{field}: #{replacement.inspect}" do
        body = response_xml.sub(/<#{field}>.*?<\/#{field}>/, replacement.gsub('FIELD', field))
        stub_request(:post, url).to_return(body: body)
        expect { SveaPayments::Payment.refund_after_settlement(token, details) }
          .to raise_error(SveaPayments::InvalidResponseError, /#{field}/)
      end
    end
  end

  [' ', '0', '000', 'OK'].each do |code|
    it "rejects malformed return code #{code.inspect}" do
      stub_request(:post, url).to_return(body: response_xml(code))
      expect { SveaPayments::Payment.refund_after_settlement(token, details) }
        .to raise_error(SveaPayments::InvalidResponseError)
    end
  end

  SveaPayments::Payment::REFUND_RESPONSE_FIELDS.each do |field|
    it "rejects duplicate #{field}" do
      stub_request(:post, url).to_return(body: response_xml.sub('</pmtc>', "<#{field}>other</#{field}></pmtc>"))
      expect { SveaPayments::Payment.refund_after_settlement(token, details) }
        .to raise_error(SveaPayments::InvalidResponseError, /Duplicate #{field}/)
    end
  end

  ['15.00', '15,0', '-15,00', '0,00'].each do |amount|
    it "rejects invalid funding amount #{amount}" do
      stub_request(:post, url).to_return(body: response_xml.sub('>15,00<', ">#{amount}<"))
      expect { SveaPayments::Payment.refund_after_settlement(token, details) }
        .to raise_error(SveaPayments::InvalidResponseError, /funding amount/)
    end
  end

  it 'preserves a valid funding amount different from the requested refund' do
    stub_request(:post, url).to_return(body: response_xml.sub('>15,00<', '>16,25<'))
    expect(SveaPayments::Payment.refund_after_settlement(token, details)['pmtc_pay_with_amount']).to eq('16,25')
  end

  it 'rejects the code-only success regression' do
    stub = stub_request(:post, url).to_return(body: '<pmtc><pmtc_returncode>00</pmtc_returncode></pmtc>')
    expect { SveaPayments::Payment.refund_after_settlement(token, details) }
      .to raise_error(SveaPayments::InvalidResponseError)
    expect(stub).to have_been_requested.once
  end
end
