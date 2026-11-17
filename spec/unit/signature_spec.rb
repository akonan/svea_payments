require 'spec_helper'
require 'digest'

# Rules: Svea DOCSLEGACY "Hash Generation" (page 262253). The documentation's
# own example hashes cannot be reproduced without the secret key they used, so
# expected values here are computed from the documented string format.
RSpec.describe SveaPayments::Signature do
  def sha512(string) = Digest::SHA512.hexdigest(string).upcase

  it 'follows the documented example: each field and the secret followed by &' do
    expect(described_class.digest(%w[123 ABC K], 'testkey')).to eq(sha512('123&ABC&K&testkey&'))
    expect(described_class.digest(%w[123 ABC K], 'testkey', algorithm: 'SHA-256'))
      .to eq(Digest::SHA256.hexdigest('123&ABC&K&testkey&').upcase)
  end

  it 'leaves out blank values together with their separator' do
    expect(described_class.digest(['123', nil, '', 'K'], 'testkey')).to eq(sha512('123&K&testkey&'))
  end

  it 'hashes UTF-8 bytes' do
    expect(described_class.digest(['Ääkkönen'], 'testkey')).to eq(sha512('Ääkkönen&testkey&'.encode('UTF-8')))
  end

  ['SHA-1', 'MD5', 'sha-512', nil].each do |algorithm|
    it "rejects unsupported algorithm #{algorithm.inspect}" do
      expect { described_class.digest(['1'], 'testkey', algorithm: algorithm) }.to raise_error(ArgumentError, /algorithm/)
    end
  end

  it 'requires a secret' do
    expect { described_class.digest(['1'], '') }.to raise_error(ArgumentError, /secret/)
    expect { described_class.digest(['1'], nil) }.to raise_error(ArgumentError, /secret/)
  end

  it 'orders payment request fields as documented, with the token after seller costs and before rows' do
    fields = {
      pmt_row_type1: '1', pmt_row_name1: 'Row one', pmt_rows: '2', pmt_row_name2: 'Row two',
      pmt_row_price_gross2: '5,00', pmt_token: 'tok', pmt_sellercosts: '0,00', pmt_id: 'id-1',
      pmt_version: '4204', pmt_action: 'NEW_PAYMENT_EXTENDED', pmt_amount: '5,00',
      pmt_paymentmethod: 'FI50', pmt_sellerid: 'not-hashed', pmt_buyeremail: 'not-hashed'
    }
    expect(described_class.payment_request(fields, 'key')).to eq(sha512(
      'NEW_PAYMENT_EXTENDED&4204&id-1&5,00&FI50&0,00&tok&Row one&1&Row two&5,00&key&'
    ))
  end

  it 'ignores rows beyond pmt_rows' do
    with_extra = { 'pmt_action' => 'A', 'pmt_rows' => '1', 'pmt_row_name1' => 'one', 'pmt_row_name2' => 'two' }
    expect(described_class.payment_request(with_extra, 'key')).to eq(sha512('A&one&key&'))
  end

  it 'puts the token last in the payment response hash' do
    fields = { 'pmt_token' => 'tok', 'pmt_escrow' => 'N', 'pmt_paymentmethod' => 'FI50', 'pmt_sellercosts' => '0,00',
               'pmt_currency' => 'EUR', 'pmt_amount' => '0,00', 'pmt_reference' => '00000000000019985242',
               'pmt_id' => 'id-1', 'pmt_version' => '4504', 'pmt_action' => 'TOKENIZE', 'pmt_hash' => 'ignored' }
    expect(described_class.payment_response(fields, 'key'))
      .to eq(sha512('TOKENIZE&4504&id-1&00000000000019985242&0,00&EUR&0,00&FI50&N&tok&key&'))
  end

  it 'includes only the status query fields present, with the token last' do
    fields = { 'pmtq_action' => 'PAYMENT_STATUS_QUERY', 'pmtq_version' => '0005', 'pmtq_sellerid' => 'seller',
               'pmtq_id' => 'id-1', 'pmtq_amount' => '568,10', 'pmtq_returncode' => '40',
               'pmtq_returntext' => 'Compensated to the seller', 'pmtq_paymentmethod' => 'FI50',
               'pmtq_token' => 'tok', 'pmtq_trackingcodes' => 'not-hashed' }
    expect(described_class.status_query_response(fields, 'key')).to eq(sha512(
      'PAYMENT_STATUS_QUERY&0005&seller&id-1&568,10&40&Compensated to the seller&FI50&tok&key&'
    ))
  end

  it 'compares hashes case-insensitively and rejects blank or different values' do
    digest = described_class.digest(['1'], 'key')
    expect(described_class.match?(digest, digest.downcase)).to be(true)
    expect(described_class.match?(digest, digest.sub(/.\z/, digest[-1] == '0' ? '1' : '0'))).to be(false)
    expect(described_class.match?(digest, nil)).to be(false)
    expect(described_class.match?('', '')).to be(false)
    expect(described_class.match?(digest, digest[0, 10])).to be(false)
  end
end
