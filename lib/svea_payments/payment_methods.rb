require_relative 'base'

module SveaPayments
  class PaymentMethods
    extend Base
    
    def self.get_available_payment_methods(token, request_details)
      uri = "#{SveaPayments.base_url}/GetPaymentMethods.pmt"


      # Convert the request details hash to URL-encoded form data
      form_data = URI.encode_www_form(request_details)
      request_uri = URI(uri + "?#{form_data}")
      xml_doc = send_get_request(request_uri, token)
      root = xml_doc.root
      # A recognized empty list is valid; an HTML/error document is not a list.
      invalid_response!('Invalid payment methods response') unless root.name == 'paymentmethods'
      invalid_response!('Payment methods response contains errors') if root.at_xpath('./errors | ./error')
      
      payment_methods = []

      root.xpath('./paymentmethod').each do |method_node|
        invalid_response!('Missing payment method code') if response_field(method_node, 'code').to_s.strip.empty?
        image_url = response_field(method_node, 'imageurl')
        payment_methods << {
          code: response_field(method_node, 'code'),
          displayname: response_field(method_node, 'displayname'),
          imageurl: {
            url: image_url,
            width: method_node.at_xpath('imageurl/@width')&.text.to_i,
            height: method_node.at_xpath('imageurl/@height')&.text.to_i,
            mimetype: method_node.at_xpath('imageurl/@mimetype')&.text
          }
        }
      end
      payment_methods
    end
  end
end
