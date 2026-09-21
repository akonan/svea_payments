require_relative 'base'

module SveaPayments
  class Payment
    extend Base
    REFUND_RESPONSE_FIELDS = %w[
      pmtc_action pmtc_version pmtc_sellerid pmtc_id pmtc_returncode
      pmtc_returntext pmtc_pay_with_reference pmtc_pay_with_recipientname
      pmtc_pay_with_amount pmtc_pay_with_iban
    ].freeze

    # Initiates a refund only. The merchant must separately fund it using the
    # returned bank transfer instructions. No money transfer or retry is done here.
    def self.refund_after_settlement(token, refund_details)
      details = refund_details.transform_keys(&:to_s)
      %w[pmtc_sellerid pmtc_id pmtc_amount pmtc_currency pmtc_cancelamount].each do |field|
        raise ArgumentError, "#{field} is required" if details[field].to_s.strip.empty?
      end
      %w[pmtc_amount pmtc_cancelamount].each do |field|
        value = details[field]
        unless value.is_a?(String) && value.match?(/\A\d+,\d{2}\z/)
          raise ArgumentError, "#{field} must be a string with two comma-separated decimals"
        end
      end
      # Protocol constants cannot be overridden by the caller.
      request = { 'pmtc_keygeneration' => '001' }.merge(details).merge(
        'pmtc_action' => 'REFUND_AFTER_SETTLEMENT',
        'pmtc_version' => '0005',
        'pmtc_canceltype' => 'REFUND_AFTER_SETTLEMENT',
        'pmtc_resptype' => 'XML'
      )
      xml = send_post_request(
        URI("#{SveaPayments.base_url}/PaymentCancel.pmt"),
        URI.encode_www_form(request), token, strict: true
      )
      root = xml.root
      if !root || root.name != 'pmtc' || root.at_xpath('./pmtc_returncode')&.text.to_s.empty?
        raise SveaPayments::InvalidResponseError, 'Missing refund response/code; request outcome may be unknown'
      end
      response = REFUND_RESPONSE_FIELDS.each_with_object({}) do |field, result|
        result[field] = root.at_xpath("./#{field}")&.text
      end
      response['errors'] = root.xpath('./errors/error').map do |error|
        { 'type' => error['type'], 'name' => error['name'], 'message' => error.text }
      end
      response
    end

    def self.create_payment(token, payment_details)
      uri = URI("#{SveaPayments.base_url}/NewPaymentExtended.pmt")

      default_values = {
        'pmt_action' => 'NEW_PAYMENT_EXTENDED',
        'pmt_version' => '0004'
      }

      final_payment_details = default_values.merge(payment_details)

      # Convert the final payment details hash to URL-encoded form data
      form_data = URI.encode_www_form(final_payment_details)
      
      xml_doc = send_post_request(uri, form_data, token)
      # Convert XML document to a Ruby hash or handle it as needed
      # Example: extracting some fields
      response_data = {
        'pmt_id' => xml_doc.xpath("//pmt_id").text,
        'pmt_reference' => xml_doc.xpath("//pmt_reference").text,
        'pmt_amount' => xml_doc.xpath("//pmt_amount").text,
        'pmt_currency' => xml_doc.xpath("//pmt_currency").text,
        'pmt_sellercosts' => xml_doc.xpath("//pmt_sellercosts").text,
        'pmt_paymentmethod' => xml_doc.xpath("//pmt_paymentmethod").text,
        'pmt_paymenturl' => xml_doc.xpath("//pmt_paymenturl").text,
        'errors' => xml_doc.xpath("//error").map { |error| error.text }
      }
      
      return response_data
    end

    def self.query_payment_status(token, pmt_id, pmt_sellerid)
      uri = URI("#{SveaPayments.base_url}/PaymentStatusQuery.pmt")

      request_data = {
        'pmtq_version' => '0005',
        'pmtq_action' => 'PAYMENT_STATUS_QUERY',
        'pmtq_sellerid' => pmt_sellerid,
        'pmtq_id' => pmt_id,
        'pmtq_resptype' => 'XML',
        'pmtq_keygeneration' => '1'
      }

      # Convert the request data hash to URL-encoded form data
      form_data = URI.encode_www_form(request_data)
      
      xml_doc = send_post_request(uri, form_data, token)
      response_data = {
        'pmtq_action' => xml_doc.xpath("//pmtq_action")&.text.to_s,
        'pmtq_version' => xml_doc.xpath("//pmtq_version")&.text.to_s,
        'pmtq_sellerid' => xml_doc.xpath("//pmtq_sellerid")&.text.to_s,
        'pmtq_id' => xml_doc.xpath("//pmtq_id")&.text.to_s,
        'pmtq_orderid' => xml_doc.xpath("//pmtq_orderid")&.text.to_s,
        'pmtq_amount' => xml_doc.xpath("//pmtq_amount")&.text.to_s,
        'pmtq_returncode' => xml_doc.xpath("//pmtq_returncode")&.text.to_s,
        'pmtq_returntext' => xml_doc.xpath("//pmtq_returntext")&.text.to_s,
        'pmtq_trackingcodes' => xml_doc.xpath("//pmtq_trackingcodes")&.text.to_s,
        'pmtq_sellercosts' => xml_doc.xpath("//pmtq_sellercosts")&.text.to_s,
        'pmtq_invoicingfee' => xml_doc.xpath("//pmtq_invoicingfee")&.text.to_s,
        'pmtq_paymentmethod' => xml_doc.xpath("//pmtq_paymentmethod")&.text.to_s,
        'pmtq_escrow' => xml_doc.xpath("//pmtq_escrow")&.text.to_s,
        'pmtq_certification' => xml_doc.xpath("//pmtq_certification")&.text.to_s,
        'pmtq_externalcode1' => xml_doc.xpath("//pmtq_externalcode1")&.text.to_s,
        'pmtq_externalcode2' => xml_doc.xpath("//pmtq_externalcode2")&.text.to_s,
        'pmtq_externaltext' => xml_doc.xpath("//pmtq_externaltext")&.text.to_s,
        'pmtq_paymentstarttimestamp' => xml_doc.xpath("//pmtq_paymentstarttimestamp")&.text.to_s,
        'pmtq_paymentdate' => xml_doc.xpath("//pmtq_paymentdate")&.text.to_s,
        'pmtq_amountrefunded' => xml_doc.xpath("//pmtq_amountrefunded")&.text.to_s,
        'pmtq_payeriban' => xml_doc.xpath("//pmtq_payeriban")&.text.to_s
      }
      return response_data
    end
  end
end
