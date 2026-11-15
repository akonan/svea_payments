require 'spec_helper'

# Contract: Svea "Refund or Cancel Payment" (DOCS page 1657012799, v21) and
# "Refunds and Cancellations examples" (page 1657014119, v4). Response bodies
# follow the documented examples; identifiers are placeholders.
RSpec.describe 'Before-settlement refunds' do
  let(:url) { 'https://test1.maksuturva.fi/PaymentCancel.pmt' }
  let(:token) { 'Basic test-only' }
  let(:full) do
    { 'pmtc_sellerid' => 'seller', 'pmtc_id' => 'order-123', 'pmtc_amount' => '568,10',
      'pmtc_currency' => 'EUR', 'pmtc_canceltype' => 'FULL_REFUND', 'pmtc_cancel_id' => 'refund-1' }
  end
  let(:partial) { full.merge('pmtc_canceltype' => 'PARTIAL_REFUND', 'pmtc_cancelamount' => '123,00') }

  def response_xml(code = '00', extra = '')
    <<~XML
      <pmtc>
          <pmtc_action>CANCEL</pmtc_action>
          <pmtc_version>0005</pmtc_version>
          <pmtc_sellerid>seller</pmtc_sellerid>
          <pmtc_id>order-123</pmtc_id>
          <pmtc_returncode>#{code}</pmtc_returncode>
          <pmtc_returntext>Provider text</pmtc_returntext>
          #{extra}
      </pmtc>
    XML
  end

  def refund(details = full)
    SveaPayments::Payment.refund_before_settlement(token, details)
  end

  it 'posts an authenticated full refund with protocol constants and no cancel amount' do
    stub = stub_request(:post, url).with(body: full.merge(
      'pmtc_action' => 'CANCEL', 'pmtc_version' => '0005', 'pmtc_resptype' => 'XML', 'pmtc_keygeneration' => '001'
    ), headers: { 'Authorization' => token, 'Content-Type' => 'application/x-www-form-urlencoded' })
      .to_return(body: response_xml)
    original = full.dup
    expect(refund).to eq(
      'pmtc_action' => 'CANCEL', 'pmtc_version' => '0005', 'pmtc_sellerid' => 'seller', 'pmtc_id' => 'order-123',
      'pmtc_returncode' => '00', 'pmtc_returntext' => 'Provider text', 'errors' => []
    )
    expect(full).to eq(original)
    expect(stub).to have_been_requested.once
  end

  %w[PARTIAL_REFUND PARTIAL_REFUND_AND_RETURN_OF_DELIVERIES].each do |type|
    it "posts a #{type} with its cancel amount, optional fields and symbol keys" do
      details = partial.merge('pmtc_canceltype' => type, 'pmtc_cancelreason' => 'DEFEC',
        'pmtc_canceldescription' => 'Palautus', 'pmtc_keygeneration' => '002').transform_keys(&:to_sym)
      stub = stub_request(:post, url).with(body: hash_including(
        'pmtc_action' => 'CANCEL', 'pmtc_canceltype' => type, 'pmtc_cancelamount' => '123,00',
        'pmtc_cancelreason' => 'DEFEC', 'pmtc_canceldescription' => 'Palautus', 'pmtc_keygeneration' => '002'
      )).to_return(body: response_xml)
      expect(refund(details)['pmtc_returncode']).to eq('00')
      expect(stub).to have_been_requested.once
    end
  end

  it 'does not let the caller override protocol constants' do
    stub = stub_request(:post, url).with(body: hash_including(
      'pmtc_action' => 'CANCEL', 'pmtc_version' => '0005', 'pmtc_resptype' => 'XML'
    )).to_return(body: response_xml)
    refund(full.merge('pmtc_action' => 'REFUND_AFTER_SETTLEMENT', 'pmtc_version' => '0001', 'pmtc_resptype' => 'JSON'))
    expect(stub).to have_been_requested.once
  end

  # 30 = already settled: the caller decides whether to use refund_after_settlement.
  %w[20 30 31 90 91 99 42].each do |code|
    it "preserves business response #{code} with structured errors, without retrying or falling back" do
      stub = stub_request(:post, url).to_return(body: response_xml(code,
        '<errors><error name="pmtc_cancelamount" type="field">pmtc_cancelamount is invalid</error>' \
        '<error type="general">Other error</error></errors>'))
      result = refund(partial)
      expect(result).to include('pmtc_returncode' => code, 'pmtc_returntext' => 'Provider text')
      expect(result['errors']).to eq([
        { 'type' => 'field', 'name' => 'pmtc_cancelamount', 'message' => 'pmtc_cancelamount is invalid' },
        { 'type' => 'general', 'name' => nil, 'message' => 'Other error' }
      ])
      expect(stub).to have_been_requested.once
    end
  end

  it 'never reports funding instructions for a before-settlement refund' do
    stub_request(:post, url).to_return(body: response_xml)
    expect(refund.keys.grep(/pay_with/)).to be_empty
  end

  %w[pmtc_sellerid pmtc_id pmtc_amount pmtc_currency pmtc_canceltype].each do |field|
    it "rejects missing #{field} before sending" do
      expect { refund(full.merge(field => ' ')) }.to raise_error(ArgumentError, /#{field}/)
      expect(WebMock).not_to have_requested(:post, url)
    end
  end

  ['REFUND_AFTER_SETTLEMENT', 'full_refund', 'CANCEL'].each do |type|
    it "rejects unsupported cancel type #{type.inspect} before sending" do
      expect { refund(full.merge('pmtc_canceltype' => type)) }.to raise_error(ArgumentError, /pmtc_canceltype/)
      expect(WebMock).not_to have_requested(:post, url)
    end
  end

  it 'rejects a cancel amount on a full refund, which the provider says must be omitted' do
    expect { refund(full.merge('pmtc_cancelamount' => '568,10')) }.to raise_error(ArgumentError, /pmtc_cancelamount/)
    expect(WebMock).not_to have_requested(:post, url)
  end

  it 'requires a cancel amount on a partial refund' do
    expect { refund(partial.reject { |key, _| key == 'pmtc_cancelamount' }) }
      .to raise_error(ArgumentError, /pmtc_cancelamount/)
    expect(WebMock).not_to have_requested(:post, url)
  end

  ['123.00', '123', 123.0, '1 234,00', '-5,00', '0,00'].each do |amount|
    it "rejects partial cancel amount #{amount.inspect} before sending" do
      expect { refund(partial.merge('pmtc_cancelamount' => amount)) }.to raise_error(ArgumentError, /pmtc_cancelamount/)
      expect(WebMock).not_to have_requested(:post, url)
    end
  end

  ['568.10', 568.1].each do |amount|
    it "rejects original amount #{amount.inspect} before sending" do
      expect { refund(full.merge('pmtc_amount' => amount)) }.to raise_error(ArgumentError, /pmtc_amount/)
      expect(WebMock).not_to have_requested(:post, url)
    end
  end

  [401, 500, 503].each do |status|
    it "raises an HTTP error for #{status} rather than reporting business success" do
      stub = stub_request(:post, url).to_return(status: status, body: response_xml)
      expect { refund }.to raise_error(SveaPayments::HTTPError) { |error| expect(error.status).to eq(status) }
      expect(stub).to have_been_requested.once
    end
  end

  it 'propagates a timeout without retrying a financial operation' do
    stub = stub_request(:post, url).to_timeout
    expect { refund }.to raise_error(Timeout::Error)
    expect(stub).to have_been_requested.once
  end

  ['', '<html/>', '<broken>', '<pmtc/>', '<pmtc><pmtc_returncode>00</pmtc_returncode></pmtc>'].each do |body|
    it "rejects an invalid response #{body.inspect} as an unknown outcome" do
      stub_request(:post, url).to_return(body: body)
      expect { refund }.to raise_error(SveaPayments::InvalidResponseError, /unknown/)
    end
  end

  %w[pmtc_action pmtc_version pmtc_sellerid pmtc_id].each do |field|
    it "rejects a mismatched #{field}" do
      stub_request(:post, url).to_return(body: response_xml.sub(%r{<#{field}>.*?</#{field}>}, "<#{field}>other</#{field}>"))
      expect { refund }.to raise_error(SveaPayments::InvalidResponseError)
    end

    it "rejects a duplicated #{field}" do
      stub_request(:post, url).to_return(body: response_xml('00', "<#{field}>other</#{field}>"))
      expect { refund }.to raise_error(SveaPayments::InvalidResponseError)
    end
  end

  it 'rejects an after-settlement reply to a before-settlement request' do
    stub_request(:post, url).to_return(body: response_xml.sub('CANCEL', 'REFUND_AFTER_SETTLEMENT'))
    expect { refund }.to raise_error(SveaPayments::InvalidResponseError)
  end

  ['0', '000', 'OK', ' '].each do |code|
    it "rejects malformed return code #{code.inspect}" do
      stub_request(:post, url).to_return(body: response_xml(code))
      expect { refund }.to raise_error(SveaPayments::InvalidResponseError)
    end
  end
end
