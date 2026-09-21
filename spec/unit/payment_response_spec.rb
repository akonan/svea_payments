require 'spec_helper'

# Characterization tests: expose current behavior, not the desired API contract.
RSpec.describe 'Current response handling' do
  let(:token) { 'Basic test-only' }

  it 'currently hides an HTTP 500 behind an empty payment result' do
    stub_request(:post, "#{SveaPayments.base_url}/NewPaymentExtended.pmt")
      .to_return(status: 500, body: '<html><body>Unavailable</body></html>')

    response = SveaPayments::Payment.create_payment(token, {})
    expect(response['pmt_id']).to eq('')
    expect(response['errors']).to eq([])
  end

  it 'currently parses CSV as XML instead of returning the original bytes' do
    csv = "date;amount\n2026-01-01;10,00\n"
    stub_request(:post, "#{SveaPayments.base_url}/GetCompensationsByTimeInterval.pmt")
      .to_return(status: 200, body: csv, headers: { 'Content-Type' => 'text/csv' })

    response = SveaPayments::Reports.get_compensation_report(
      '01.01.2026', '02.01.2026', 'test-seller', token, format: 'CSV'
    )
    expect(response).to be_a(Nokogiri::XML::Document)
    expect(response.to_s).not_to eq(csv)
  end
end
