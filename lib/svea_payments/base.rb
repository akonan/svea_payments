require 'net/http'
require 'uri'
require 'nokogiri'

module SveaPayments
  module Base
    def send_post_request(uri, form_data, token)
      request = Net::HTTP::Post.new(uri)
      request.content_type = 'application/x-www-form-urlencoded'
      request.body = form_data
      request['Authorization'] = token

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(request)
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