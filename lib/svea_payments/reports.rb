require_relative 'base'

module SveaPayments
  class Reports
    extend Base

    def self.get_compensation_report(start_date, end_date, seller_id, token, format: 'XML', key_generation: '001')
      raise ArgumentError, 'format must be XML or CSV' unless %w[XML CSV].include?(format)
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
      xml_doc = send_post_request(uri, encoded_form_data, token, raw: format == 'CSV')
      
      if format == 'XML'
        root = xml_doc.root
        invalid_response!('Missing report resultCode') if response_field(root, 'resultCode').to_s.strip.empty?
        validate_identity(root, { 'sellerId' => seller_id }, required: false)
        # Parse and return the XML response
        {
          'version' => response_field(root, 'version'),
          'timestamp' => response_field(root, 'timestamp'),
          'sellerId' => response_field(root, 'sellerId'),
          'resultCode' => response_field(root, 'resultCode'),
          'resultText' => response_field(root, 'resultText'),
          'keyGeneration' => response_field(root, 'keyGeneration'),
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
          'compensationCode' => response_field(comp, 'compensationCode'),
          'compensationType' => response_field(comp, 'compensationType'),
          'compensationDate' => response_field(comp, 'compensationDate'),
          'reference' => response_field(comp, 'reference'),
          'grossAmount' => response_field(comp, 'grossAmount'),
          'netAmount' => response_field(comp, 'netAmount'),
          'refundedAmount' => response_field(comp, 'refundedAmount'),
          'commission' => response_field(comp, 'commission'),
          'commissionVat' => response_field(comp, 'commissionVat'),
          'orders' => parse_orders(comp)
        }
      end
    end

    def self.parse_orders(compensation)
      compensation.xpath('.//order').map do |order|
        {
          'bundleCode' => response_field(order, 'bundleCode'),
          'orderNumber' => response_field(order, 'orderNumber'),
          'originalReference' => response_field(order, 'originalReference'),
          'paymentId' => response_field(order, 'paymentId'),
          'sellerGrossAmount' => response_field(order, 'sellerGrossAmount'),
          'sellerNetAmount' => response_field(order, 'sellerNetAmount'),
          'refundedAmount' => response_field(order, 'refundedAmount'),
          'commission' => response_field(order, 'commission'),
          'commissionVat' => response_field(order, 'commissionVat'),
          'commissionVatRate' => response_field(order, 'commissionVatRate'),
          'buyerPaymentDateTime' => response_field(order, 'buyerPaymentDateTime'),
          'paymentMethod' => response_field(order, 'paymentMethod'),
          'paymentMethodGroup' => response_field(order, 'paymentMethodGroup'),
          'marketplaceCommission' => response_field(order, 'marketplaceCommission'),
          'marketplaceCommissionReference' => response_field(order, 'marketplaceCommissionReference'),
          'marketplaceCommissionCompensationDate' => response_field(order, 'marketplaceCommissionCompensationDate')
        }
      end
    end
  end
end
