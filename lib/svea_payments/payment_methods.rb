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
      
      payment_methods = []

      xml_doc.xpath('//paymentmethod').each do |method_node|
        payment_methods << {
          code: method_node.at_xpath('code')&.text,
          displayname: method_node.at_xpath('displayname')&.text,
          imageurl: {
            url: method_node.at_xpath('imageurl')&.text,
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