require 'net/http'
require 'uri'
require 'nokogiri'

module SveaPayments
  module Base
    def send_post_request(uri, form_data, token, raw: false)
      request = Net::HTTP::Post.new(uri)
      request.content_type = 'application/x-www-form-urlencoded'
      request.body = form_data
      request['Authorization'] = token

      body = perform_request(uri, request)
      raw ? body : parse_xml(body)
    end

    def send_get_request(uri, token)
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = token

      parse_xml(perform_request(uri, request))
    end

    private

    def perform_request(uri, request)
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https',
        open_timeout: 10, read_timeout: 30, write_timeout: 30) do |http|
        http.max_retries = 0
        http.request(request)
      end
      raise SveaPayments::HTTPError, response.code unless response.is_a?(Net::HTTPSuccess)
      response.body.to_s
    end

    def parse_xml(body)
      xml = Nokogiri::XML(body) { |config| config.strict.nonet }
      invalid_response!('Missing XML root') unless xml.root
      xml
    rescue Nokogiri::XML::SyntaxError
      invalid_response!('Invalid XML response')
    end

    def invalid_response!(message)
      raise SveaPayments::InvalidResponseError, "#{message}; request outcome may be unknown"
    end

    # Never concatenate duplicates or borrow values from a nested record.
    def response_field(node, name)
      matches = node.xpath("./#{name}")
      if matches.size > 1 || matches.any? { |field| field.element_children.any? }
        invalid_response!("Ambiguous #{name}")
      end
      matches.first&.text
    end

    def validate_identity(node, expected, required: true)
      expected.each do |field, value|
        actual = response_field(node, field)
        next if actual.nil? && !required
        invalid_response!("Mismatched or missing #{field}") unless actual == value.to_s
      end
    end
  end
end
