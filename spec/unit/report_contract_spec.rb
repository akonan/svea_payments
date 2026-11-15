require 'spec_helper'
require 'date'

# Contract: Svea "Report Request" (DOCS page 1657012958, v26), "Retrieve
# Settlement Reports examples" (page 1657014136) and GetCompensationsResponse.xsd.
# Result codes per the XSD: 00 success, 91 service not available for the seller,
# 95 errors in request, 99 error. Bodies follow the documented examples.
RSpec.describe 'Settlement report contract' do
  let(:url) { "#{SveaPayments.base_url}/GetCompensationsByTimeInterval.pmt" }
  let(:ok_xml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <getCompensationsResponse>
        <version>0003</version>
        <timestamp>2024-01-09T09:16:00+02:00</timestamp>
        <sellerId>seller</sellerId>
        <resultCode>00</resultCode>
        <resultText>OK</resultText>
        <keyGeneration>001</keyGeneration>
        <compensations>
          <compensation>
            <compensationCode>10000000000000700000</compensationCode>
            <compensationType>BUNDLE</compensationType>
            <compensationDate>2023-11-15T00:00:00+02:00</compensationDate>
            <reference>99990000000000191247</reference>
            <grossAmount>529.35</grossAmount>
            <netAmount>410.95</netAmount>
            <refundedAmount>108.95</refundedAmount>
            <commission>9.45</commission>
            <commissionVat>1.54</commissionVat>
            <orders>
              <order>
                <bundleCode>10000000000000700000</bundleCode>
                <orderNumber>2006</orderNumber>
                <paymentId>1006</paymentId>
                <sellerGrossAmount>199</sellerGrossAmount>
                <sellerNetAmount>138.5</sellerNetAmount>
                <refundedAmount>59</refundedAmount>
                <commission>1.5</commission>
                <paymentMethod>FIOB</paymentMethod>
              </order>
              <order>
                <orderNumber>2007</orderNumber>
                <paymentId>1007</paymentId>
                <refundedAmount>49.95</refundedAmount>
                <commission>7.95</commission>
              </order>
            </orders>
          </compensation>
          <compensation>
            <compensationType>SINGLE</compensationType>
            <refundedAmount>0.00</refundedAmount>
            <orders><order><orderNumber>2008</orderNumber><paymentId>1008</paymentId></order></orders>
          </compensation>
        </compensations>
      </getCompensationsResponse>
    XML
  end

  def error_xml(code, text)
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <ns2:getCompensationsResponse xmlns:ns2="https://www.maksuturva.fi/smtschema/GetCompensationsResponse.xsd">
        <timestamp>2014-10-16T14:09:17.000+03:00</timestamp>
        <sellerId>seller</sellerId>
        <resultCode>#{code}</resultCode>
        <resultText>#{text}</resultText>
        <keyGeneration>1</keyGeneration>
      </ns2:getCompensationsResponse>
    XML
  end

  def report
    SveaPayments::Reports.get_compensation_report(Date.new(2026, 1, 1), Date.new(2026, 1, 2), 'seller', 'Basic fake')
  end

  it 'parses the documented bundle and single settlements with their own orders' do
    stub_request(:post, url).to_return(body: ok_xml)
    result = report
    expect(result).to include('version' => '0003', 'sellerId' => 'seller', 'resultCode' => '00', 'resultText' => 'OK')
    bundle, single = result['compensations']
    expect(bundle).to include('compensationType' => 'BUNDLE', 'grossAmount' => '529.35', 'refundedAmount' => '108.95')
    expect(bundle['orders'].map { |order| order['paymentId'] }).to eq(%w[1006 1007])
    expect(bundle['orders'].first).to include('refundedAmount' => '59', 'paymentMethod' => 'FIOB')
    expect(single).to include('compensationType' => 'SINGLE', 'refundedAmount' => '0.00')
    expect(single['orders'].map { |order| order['paymentId'] }).to eq(%w[1008])
  end

  it 'accepts the namespace-prefixed root used in documented replies' do
    stub_request(:post, url).to_return(body: ok_xml.sub('<getCompensationsResponse>',
      '<ns2:getCompensationsResponse xmlns:ns2="https://www.maksuturva.fi/smtschema/GetCompensationsResponse.xsd">')
      .sub('</getCompensationsResponse>', '</ns2:getCompensationsResponse>'))
    expect(report['compensations'].size).to eq(2)
  end

  it 'returns the documented "No events found." reply as an empty report, keeping its code' do
    stub_request(:post, url).to_return(body: error_xml('95', 'No events found.'))
    expect(report).to include('resultCode' => '95', 'resultText' => 'No events found.', 'compensations' => [])
  end

  {
    '95' => 'Errors in: {[gc_enddate:the given interval is too big. Maximum allowed is one month.]}',
    '91' => 'Service not available',
    '99' => 'Error',
    '42' => 'Undocumented'
  }.each do |code, text|
    it "raises a report error for result code #{code} instead of returning an empty report" do
      stub = stub_request(:post, url).to_return(body: error_xml(code, text))
      expect { report }.to raise_error(SveaPayments::ReportError) { |error|
        expect(error).to have_attributes(code: code, text: text)
        expect(error).to be_a(SveaPayments::Error)
      }
      expect(stub).to have_been_requested.once
    end
  end

  it 'does not treat a 00 reply without settlements as an error' do
    stub_request(:post, url).to_return(body: '<getCompensationsResponse><resultCode>00</resultCode></getCompensationsResponse>')
    expect(report['compensations']).to eq([])
  end

  it 'ignores settlement-like elements outside the documented collection path' do
    body = ok_xml.sub('</getCompensationsResponse>',
      '<other><compensation><compensationType>STRAY</compensationType></compensation></other></getCompensationsResponse>')
    stub_request(:post, url).to_return(body: body)
    expect(report['compensations'].map { |row| row['compensationType'] }).to eq(%w[BUNDLE SINGLE])
  end

  it 'ignores orders nested outside a settlement\'s own orders element' do
    body = ok_xml.sub('<compensationType>SINGLE</compensationType>',
      '<compensationType>SINGLE</compensationType><extra><order><paymentId>stray</paymentId></order></extra>')
    stub_request(:post, url).to_return(body: body)
    expect(report['compensations'].last['orders'].map { |order| order['paymentId'] }).to eq(%w[1008])
  end

  ['<report><resultCode>00</resultCode></report>',
   '<getCompensationsResponse><resultText>OK</resultText></getCompensationsResponse>',
   '<getCompensationsResponse><resultCode>0</resultCode></getCompensationsResponse>',
   '<getCompensationsResponse><resultCode>OK</resultCode></getCompensationsResponse>'].each do |body|
    it "rejects an unrecognised report reply #{body}" do
      stub_request(:post, url).to_return(body: body)
      expect { report }.to raise_error(SveaPayments::InvalidResponseError)
    end
  end
end
