require_relative 'base'

module SveaPayments
  class Reports
    extend Base

    def self.get_compensation_report(start_date, end_date, seller_id, token, format: 'XML', key_generation: '001')
      uri = URI("#{SveaPayments.base_url}/GetCompensationsByTimeInterval.pmt")
      
      # Format dates as required by the API (dd.MM.yyyy)
      formatted_start_date = start_date.strftime('%d.%m.%Y') if start_date.respond_to?(:strftime)
      formatted_end_date = end_date.strftime('%d.%m.%Y') if end_date.respond_to?(:strftime)
      
      # Build form data parameters
      form_data = {
        'gc_action' => format == 'XML' ? 'GET_SETTLEMENTS_XML' : 'GET_SETTLEMENTS_CSV',
        'gc_version' => '0003',
        'gc_sellerid' => seller_id,
        'gc_begindate' => formatted_start_date || start_date,
        'gc_enddate' => formatted_end_date || end_date,
        'gc_keygeneration' => key_generation
      }
      
      # Convert the form data hash to URL-encoded form data
      encoded_form_data = URI.encode_www_form(form_data)
      
      # Send POST request and return the response
      xml_doc = send_post_request(uri, encoded_form_data, token)
      
      if format == 'XML'
        # Parse and return the XML response
        {
          'version' => xml_doc.at_xpath('//version')&.text,
          'timestamp' => xml_doc.at_xpath('//timestamp')&.text,
          'sellerId' => xml_doc.at_xpath('//sellerId')&.text,
          'resultCode' => xml_doc.at_xpath('//resultCode')&.text,
          'resultText' => xml_doc.at_xpath('//resultText')&.text,
          'keyGeneration' => xml_doc.at_xpath('//keyGeneration')&.text,
          'compensations' => parse_compensations(xml_doc)
        }
      else
        # Return raw response for CSV format
        xml_doc
      end
    end

    private

    def self.parse_compensations(xml_doc)
      xml_doc.xpath('//compensation').map do |comp|
        {
          'compensationCode' => comp.at_xpath('.//compensationCode')&.text,
          'compensationType' => comp.at_xpath('.//compensationType')&.text,
          'compensationDate' => comp.at_xpath('.//compensationDate')&.text,
          'reference' => comp.at_xpath('.//reference')&.text,
          'grossAmount' => comp.at_xpath('.//grossAmount')&.text,
          'netAmount' => comp.at_xpath('.//netAmount')&.text,
          'refundedAmount' => comp.at_xpath('.//refundedAmount')&.text,
          'commission' => comp.at_xpath('.//commission')&.text,
          'commissionVat' => comp.at_xpath('.//commissionVat')&.text,
          'orders' => parse_orders(comp)
        }
      end
    end

    def self.parse_orders(compensation)
      compensation.xpath('.//order').map do |order|
        {
          'bundleCode' => order.at_xpath('.//bundleCode')&.text,
          'orderNumber' => order.at_xpath('.//orderNumber')&.text,
          'originalReference' => order.at_xpath('.//originalReference')&.text,
          'paymentId' => order.at_xpath('.//paymentId')&.text,
          'sellerGrossAmount' => order.at_xpath('.//sellerGrossAmount')&.text,
          'sellerNetAmount' => order.at_xpath('.//sellerNetAmount')&.text,
          'refundedAmount' => order.at_xpath('.//refundedAmount')&.text,
          'commission' => order.at_xpath('.//commission')&.text,
          'commissionVat' => order.at_xpath('.//commissionVat')&.text,
          'commissionVatRate' => order.at_xpath('.//commissionVatRate')&.text,
          'buyerPaymentDateTime' => order.at_xpath('.//buyerPaymentDateTime')&.text,
          'paymentMethod' => order.at_xpath('.//paymentMethod')&.text,
          'paymentMethodGroup' => order.at_xpath('.//paymentMethodGroup')&.text,
          'marketplaceCommission' => order.at_xpath('.//marketplaceCommission')&.text,
          'marketplaceCommissionReference' => order.at_xpath('.//marketplaceCommissionReference')&.text,
          'marketplaceCommissionCompensationDate' => order.at_xpath('.//marketplaceCommissionCompensationDate')&.text
        }
      end
    end
  end
end 