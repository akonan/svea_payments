require 'net/http'
require 'uri'
require 'nokogiri'

module SveaPayments
  module Base
    def send_post_request(uri, form_data, token, strict: false)
      request = Net::HTTP::Post.new(uri)
      request.content_type = 'application/x-www-form-urlencoded'
      request.body = form_data
      request['Authorization'] = token

      options = { use_ssl: uri.scheme == 'https' }
      options.merge!(open_timeout: 10, read_timeout: 30, write_timeout: 30) if strict
      response = Net::HTTP.start(uri.hostname, uri.port, **options) do |http|
        http.max_retries = 0 if strict
        http.request(request)
      end

      if strict
        raise SveaPayments::HTTPError, response.code unless response.is_a?(Net::HTTPSuccess)

        begin
          return Nokogiri::XML(response.body) { |config| config.strict.nonet }
        rescue Nokogiri::XML::SyntaxError
          raise SveaPayments::InvalidResponseError, 'Invalid XML response; request outcome may be unknown'
        end
      end

      Nokogiri::XML(response.body)
    end

    def send_get_request(uri, token)
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = token

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(request)
      end

      Nokogiri::XML(response.body)
    end
  end
end
