require 'spec_helper'

RSpec.describe 'Transport policy' do
  %i[post get].each do |method|
    it "sets bounded timeouts and zero automatic retries for #{method}" do
      uri = URI('https://test1.maksuturva.fi/example')
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return('<response/>')
      http = instance_double(Net::HTTP)
      expect(http).to receive(:max_retries=).with(0)
      expect(http).to receive(:request).with(an_instance_of(method == :post ? Net::HTTP::Post : Net::HTTP::Get)).and_return(response)
      expect(Net::HTTP).to receive(:start).with(uri.hostname, 443,
        use_ssl: true, open_timeout: 10, read_timeout: 30, write_timeout: 30).and_yield(http)
      client = Object.new.extend(SveaPayments::Base)
      result = method == :post ? client.send_post_request(uri, 'a=b', 'Basic fake') : client.send_get_request(uri, 'Basic fake')
      expect(result.root.name).to eq('response')
    end
  end
end
