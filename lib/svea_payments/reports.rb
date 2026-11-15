require_relative 'base'

module SveaPayments
  class Reports
    extend Base

    NO_EVENTS = /\ANo events found\.?\z/i

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
        invalid_response!('Invalid report root') unless root.name == 'getCompensationsResponse'
        result_code = response_field(root, 'resultCode')
        invalid_response!('Missing or invalid report resultCode') unless result_code&.match?(/\A\d{2}\z/)
        validate_identity(root, { 'sellerId' => seller_id }, required: false)
        result_text = response_field(root, 'resultText')
        # Svea reports a period without settlements as 95 "No events found.";
        # every other non-00 reply is a failure and carries no report data.
        unless result_code == '00' || (result_code == '95' && result_text.to_s.strip.match?(NO_EVENTS))
          raise SveaPayments::ReportError.new(result_code, result_text)
        end
        # Parse and return the XML response
        {
          'version' => response_field(root, 'version'),
          'timestamp' => response_field(root, 'timestamp'),
          'sellerId' => response_field(root, 'sellerId'),
          'resultCode' => result_code,
          'resultText' => result_text,
          'keyGeneration' => response_field(root, 'keyGeneration'),
          'compensations' => parse_compensations(root)
        }
      else
        # Return raw response for CSV format
        xml_doc
      end
    end

    private

    # Documented path: getCompensationsResponse/compensations/compensation/orders/order.
    def self.parse_compensations(root)
      root.xpath('./compensations/compensation').map do |comp|
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
      compensation.xpath('./orders/order').map do |order|
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
