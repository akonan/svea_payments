require 'spec_helper'
require 'date'

# Synthetic regression fixtures based on the fields exposed by this gem.
# These are not recordings of live Svea replies or proof of the full API schema.
RSpec.describe 'Non-refund operation contracts' do
  let(:token) { 'Basic fake' }
  let(:base) { SveaPayments.base_url }
  let(:create_xml) { '<pmt><pmt_id>payment</pmt_id><pmt_paymenturl>https://example.test/pay</pmt_paymenturl><pmt_amount>12,00</pmt_amount></pmt>' }
  let(:query_xml) { '<pmtq><pmtq_id>payment</pmtq_id><pmtq_sellerid>seller</pmtq_sellerid><pmtq_returncode>00</pmtq_returncode><pmtq_amount>12,00</pmtq_amount></pmtq>' }
  let(:report_xml) { '<report><sellerId>seller</sellerId><resultCode>00</resultCode><compensations/></report>' }
  let(:methods_xml) { '<paymentmethods><paymentmethod><code>FI01</code><displayname>Bank</displayname><imageurl width="80" height="40" mimetype="image/png">https://example.test/icon.png</imageurl></paymentmethod></paymentmethods>' }

  def invoke(operation)
    case operation
    when :create then SveaPayments::Payment.create_payment(token, pmt_id: 'payment')
    when :query then SveaPayments::Payment.query_payment_status(token, 'payment', 'seller')
    when :report, :csv
      SveaPayments::Reports.get_compensation_report(Date.new(2026, 1, 1), '02.01.2026', 'seller', token,
        format: operation == :csv ? 'CSV' : 'XML')
    when :methods then SveaPayments::PaymentMethods.get_available_payment_methods(token, sellerid: 'seller')
    end
  end

  def endpoint(operation)
    path = { create: 'NewPaymentExtended.pmt', query: 'PaymentStatusQuery.pmt',
      report: 'GetCompensationsByTimeInterval.pmt', csv: 'GetCompensationsByTimeInterval.pmt',
      methods: 'GetPaymentMethods.pmt?sellerid=seller' }.fetch(operation)
    "#{base}/#{path}"
  end

  %i[create query report csv methods].each do |operation|
    [301, 401, 500, 503].each do |status|
      it "rejects HTTP #{status} for #{operation}, even with a successful-looking body" do
        body = operation == :csv ? "amount\n12,00\n" : public_send("#{operation}_xml")
        stub = stub_request(operation == :methods ? :get : :post, endpoint(operation)).to_return(status: status, body: body)
        expect { invoke(operation) }.to raise_error(SveaPayments::HTTPError) { |error| expect(error.status).to eq(status) }
        expect(stub).to have_been_requested.once
      end
    end

    it "propagates #{operation} timeouts without retrying" do
      stub = stub_request(operation == :methods ? :get : :post, endpoint(operation)).to_timeout
      expect { invoke(operation) }.to raise_error(Timeout::Error)
      expect(stub).to have_been_requested.once
    end

    next if operation == :csv
    ['', '<broken>', '<html/>'].each do |body|
      it "rejects invalid #{operation} XML #{body.inspect}" do
        stub_request(operation == :methods ? :get : :post, endpoint(operation)).to_return(body: body)
        expect { invoke(operation) }.to raise_error(SveaPayments::InvalidResponseError)
      end
    end
  end

  it 'posts create defaults/auth and returns successful fields without mutating input' do
    details = { pmt_id: 'payment' }.freeze
    stub_request(:post, endpoint(:create)).with(body: {
      'pmt_id' => 'payment', 'pmt_action' => 'NEW_PAYMENT_EXTENDED', 'pmt_version' => '0004'
    }, headers: { 'Authorization' => token }).to_return(body: create_xml)
    expect(SveaPayments::Payment.create_payment(token, details)).to include(
      'pmt_id' => 'payment', 'pmt_paymenturl' => 'https://example.test/pay', 'pmt_amount' => '12,00', 'errors' => [])
  end

  it 'preserves create business errors without requiring success fields' do
    stub_request(:post, endpoint(:create)).to_return(body: '<pmt><errors><error>Rejected</error></errors></pmt>')
    expect(invoke(:create)).to include('errors' => ['Rejected'], 'pmt_paymenturl' => '')
  end

  it 'rejects incomplete create success' do
    stub_request(:post, endpoint(:create)).to_return(body: '<pmt><pmt_id>payment</pmt_id></pmt>')
    expect { invoke(:create) }.to raise_error(SveaPayments::InvalidResponseError)
  end

  it 'rejects duplicate create fields' do
    stub_request(:post, endpoint(:create)).to_return(body: create_xml.sub('</pmt>', '<pmt_id>other</pmt_id></pmt>'))
    expect { invoke(:create) }.to raise_error(SveaPayments::InvalidResponseError)
  end

  it 'rejects a mismatched create payment ID' do
    stub_request(:post, endpoint(:create)).to_return(body: create_xml.sub('>payment<', '>other<'))
    expect { invoke(:create) }.to raise_error(SveaPayments::InvalidResponseError)
  end

  it 'does not accept nested scalar query values' do
    stub_request(:post, endpoint(:query)).to_return(body: query_xml.sub('>payment<', '><nested>payment</nested><'))
    expect { invoke(:query) }.to raise_error(SveaPayments::InvalidResponseError)
  end

  it 'rejects a mismatched identity even on a business rejection' do
    stub_request(:post, endpoint(:query)).to_return(body: query_xml.sub('>00<', '>90<').sub('>payment<', '>other<'))
    expect { invoke(:query) }.to raise_error(SveaPayments::InvalidResponseError)
  end

  it 'rejects a report from another seller' do
    stub_request(:post, endpoint(:report)).to_return(body: report_xml.sub('>seller<', '>other<'))
    expect { invoke(:report) }.to raise_error(SveaPayments::InvalidResponseError)
  end

  it 'rejects duplicate order amounts instead of choosing one' do
    body = '<report><resultCode>00</resultCode><compensation><order><commission>1,00</commission><commission>2,00</commission></order></compensation></report>'
    stub_request(:post, endpoint(:report)).to_return(body: body)
    expect { invoke(:report) }.to raise_error(SveaPayments::InvalidResponseError)
  end

  it 'rejects duplicate method codes' do
    stub_request(:get, endpoint(:methods)).to_return(body: methods_xml.sub('</paymentmethod>', '<code>FI02</code></paymentmethod>'))
    expect { invoke(:methods) }.to raise_error(SveaPayments::InvalidResponseError)
  end

  it 'posts query identity/auth and returns correlated success' do
    stub_request(:post, endpoint(:query)).with(body: hash_including('pmtq_id' => 'payment', 'pmtq_sellerid' => 'seller'),
      headers: { 'Authorization' => token }).to_return(body: query_xml)
    expect(invoke(:query)).to include('pmtq_id' => 'payment', 'pmtq_sellerid' => 'seller', 'pmtq_returncode' => '00')
  end

  %w[20 90 99 42].each do |code|
    it "preserves query business code #{code} without inventing success" do
      stub_request(:post, endpoint(:query)).to_return(body: "<pmtq><pmtq_returncode>#{code}</pmtq_returncode><pmtq_returntext>Provider text</pmtq_returntext></pmtq>")
      expect(invoke(:query)).to include('pmtq_returncode' => code, 'pmtq_returntext' => 'Provider text')
    end
  end

  %w[pmtq_id pmtq_sellerid].each do |field|
    %w[missing mismatched duplicated].each do |problem|
      it "rejects #{problem} query #{field}" do
        body = query_xml.dup
        case problem
        when 'missing' then body.sub!(/<#{field}>.*?<\/#{field}>/, '')
        when 'mismatched' then body.sub!(/<#{field}>.*?<\/#{field}>/, "<#{field}>other</#{field}>")
        when 'duplicated' then body.sub!('</pmtq>', "<#{field}>other</#{field}></pmtq>")
        end
        stub_request(:post, endpoint(:query)).to_return(body: body)
        expect { invoke(:query) }.to raise_error(SveaPayments::InvalidResponseError)
      end
    end
  end

  ['<other><pmtq_returncode>00</pmtq_returncode></other>',
   '<pmtq><pmtq_returncode>00</pmtq_returncode><pmtq_returncode>00</pmtq_returncode></pmtq>',
   '<pmtq><pmtq_returncode> </pmtq_returncode></pmtq>'].each do |body|
    it "rejects ambiguous query result #{body}" do
      stub_request(:post, endpoint(:query)).to_return(body: body)
      expect { invoke(:query) }.to raise_error(SveaPayments::InvalidResponseError)
    end
  end

  it 'formats report dates and preserves an explicitly empty successful report' do
    stub_request(:post, endpoint(:report)).with(body: hash_including(
      'gc_begindate' => '01.01.2026', 'gc_enddate' => '02.01.2026', 'gc_action' => 'GET_SETTLEMENTS_XML'
    )).to_return(body: report_xml)
    expect(invoke(:report)).to include('sellerId' => 'seller', 'resultCode' => '00', 'compensations' => [])
  end

  it 'preserves report business rejection text/code' do
    stub_request(:post, endpoint(:report)).to_return(body: '<report><resultCode>90</resultCode><resultText>Rejected</resultText></report>')
    expect(invoke(:report)).to include('resultCode' => '90', 'resultText' => 'Rejected')
  end

  it 'preserves parent totals regardless of child ordering, across multiple settlements and orders' do
    body = '<report><resultCode>00</resultCode><compensations>' +
      '<compensation><orders><order><commission>1,00</commission><refundedAmount>2,00</refundedAmount></order>' +
      '<order><commission>3,00</commission></order></orders><commission>9,00</commission><refundedAmount>8,00</refundedAmount></compensation>' +
      '<compensation><orders><order><commission>7,00</commission><refundedAmount>6,00</refundedAmount></order></orders></compensation>' +
      '</compensations></report>'
    stub_request(:post, endpoint(:report)).to_return(body: body)
    rows = invoke(:report)['compensations']
    expect(rows.size).to eq(2)
    expect(rows[0]).to include('commission' => '9,00', 'refundedAmount' => '8,00')
    expect(rows[0]['orders'].map { |o| o['commission'] }).to eq(['1,00', '3,00'])
    expect(rows[1]).to include('commission' => nil, 'refundedAmount' => nil)
    expect(rows[1]['orders'].first).to include('commission' => '7,00', 'refundedAmount' => '6,00')
  end

  it 'rejects duplicate report scalar fields' do
    stub_request(:post, endpoint(:report)).to_return(body: report_xml.sub('</report>', '<resultCode>90</resultCode></report>'))
    expect { invoke(:report) }.to raise_error(SveaPayments::InvalidResponseError)
  end

  it 'returns CSV bytes including UTF-8, quoted separators, and CRLF unchanged' do
    csv = "name;amount\r\n\"Ää;Öö\";12,00\r\n"
    stub_request(:post, endpoint(:csv)).with(body: hash_including('gc_action' => 'GET_SETTLEMENTS_CSV')).to_return(body: csv)
    expect(invoke(:csv).bytes).to eq(csv.bytes)
  end

  ['xml', :CSV, nil, 'JSON'].each do |format|
    it "rejects unsupported report format #{format.inspect} before sending" do
      expect { SveaPayments::Reports.get_compensation_report('start', 'end', 'seller', token, format: format) }
        .to raise_error(ArgumentError, /format/)
      expect(WebMock).not_to have_requested(:post, endpoint(:report))
    end
  end

  it 'returns payment method metadata and image dimensions' do
    stub_request(:get, endpoint(:methods)).with(headers: { 'Authorization' => token }).to_return(body: methods_xml)
    expect(invoke(:methods)).to eq([{ code: 'FI01', displayname: 'Bank', imageurl: {
      url: 'https://example.test/icon.png', width: 80, height: 40, mimetype: 'image/png'
    } }])
  end

  it 'accepts an explicitly empty method list' do
    stub_request(:get, endpoint(:methods)).to_return(body: '<paymentmethods/>')
    expect(invoke(:methods)).to eq([])
  end

  ['<paymentmethods><error>Rejected</error></paymentmethods>',
   '<paymentmethods><paymentmethod><displayname>Bank</displayname></paymentmethod></paymentmethods>'].each do |body|
    it "rejects an unusable method list #{body}" do
      stub_request(:get, endpoint(:methods)).to_return(body: body)
      expect { invoke(:methods) }.to raise_error(SveaPayments::InvalidResponseError)
    end
  end
end
