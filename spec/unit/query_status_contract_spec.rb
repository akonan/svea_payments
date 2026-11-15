require 'spec_helper'

RSpec.describe 'Provider-documented query status semantics' do
  def reply(code, id: 'payment', seller: 'seller')
    fields = "<pmtq_returncode>#{code}</pmtq_returncode><pmtq_returntext>Provider text</pmtq_returntext>"
    fields += "<pmtq_id>#{id}</pmtq_id>" unless id.nil?
    fields += "<pmtq_sellerid>#{seller}</pmtq_sellerid>" unless seller.nil?
    stub_request(:post, "#{SveaPayments.base_url}/PaymentStatusQuery.pmt")
      .to_return(body: "<pmtq>#{fields}</pmtq>")
  end

  def query
    SveaPayments::Payment.query_payment_status('Basic fake', 'payment', 'seller')
  end

  %w[20 30 40 91 92 93 95 98].each do |code|
    it "preserves confirmed code #{code} with correlated identities" do
      reply(code)
      expect(query).to include('pmtq_returncode' => code, 'pmtq_id' => 'payment', 'pmtq_sellerid' => 'seller')
    end

    [{ id: nil }, { seller: nil }, { id: '', seller: '' }, { id: 'other' }, { seller: 'other' }].each do |override|
      it "rejects confirmed code #{code} with #{override.inspect}" do
        reply(code, **override)
        expect { query }.to raise_error(SveaPayments::InvalidResponseError)
      end
    end
  end

  %w[00 10 11 15 19 99].each do |code|
    it "preserves non-confirmed or cancelled code #{code} without requiring identities" do
      reply(code, id: nil, seller: nil)
      expect(query).to include('pmtq_returncode' => code, 'pmtq_returntext' => 'Provider text')
    end

    it "still rejects a supplied mismatching ID for #{code}" do
      reply(code, id: 'other')
      expect { query }.to raise_error(SveaPayments::InvalidResponseError)
    end
  end

  it 'raises for query failure 01 instead of returning an unpaid-looking result' do
    reply('01')
    expect { query }.to raise_error(SveaPayments::Error, /query failed/i)
  end

  it 'raises for query failure 01 with no echoed identities' do
    reply('01', id: nil, seller: nil)
    expect { query }.to raise_error(SveaPayments::Error, /query failed/i)
  end
end
