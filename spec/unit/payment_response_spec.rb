require 'spec_helper'

RSpec.describe 'Response handling regressions' do
  let(:token) { 'Basic test-only' }

  it 'raises for an HTTP 500 instead of returning an empty payment result' do
    stub_request(:post, "#{SveaPayments.base_url}/NewPaymentExtended.pmt")
      .to_return(status: 500, body: '<html><body>Unavailable</body></html>')

    expect { SveaPayments::Payment.create_payment(token, {}) }
      .to raise_error(SveaPayments::HTTPError) { |error| expect(error.status).to eq(500) }
  end

  it 'returns the original CSV bytes' do
    csv = "date;amount\n2026-01-01;10,00\n"
    stub_request(:post, "#{SveaPayments.base_url}/GetCompensationsByTimeInterval.pmt")
      .to_return(status: 200, body: csv, headers: { 'Content-Type' => 'text/csv' })

    response = SveaPayments::Reports.get_compensation_report(
      '01.01.2026', '02.01.2026', 'test-seller', token, format: 'CSV'
    )
    expect(response).to eq(csv)
  end
end
