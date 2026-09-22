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
        URI.encode_www_form(request), token
      )
      root = xml.root
      if !root || root.name != 'pmtc' || root.at_xpath('./pmtc_returncode')&.text.to_s.empty?
        raise SveaPayments::InvalidResponseError, 'Missing refund response/code; request outcome may be unknown'
      end
      response = REFUND_RESPONSE_FIELDS.each_with_object({}) do |field, result|
        result[field] = root.at_xpath("./#{field}")&.text
      end
      # Reject ambiguous replies instead of choosing the first duplicate field.
      REFUND_RESPONSE_FIELDS.each do |field|
        if root.xpath("./#{field}").length > 1
          raise SveaPayments::InvalidResponseError, "Duplicate #{field}; request outcome may be unknown"
        end
      end
      %w[pmtc_action pmtc_version pmtc_sellerid pmtc_id].each do |field|
        unless response[field] == request[field].to_s
          raise SveaPayments::InvalidResponseError, "Mismatched or missing #{field}; request outcome may be unknown"
        end
      end
      unless response['pmtc_returncode'].match?(/\A\d{2}\z/)
        raise SveaPayments::InvalidResponseError, 'Invalid refund response code; request outcome may be unknown'
      end
      if response['pmtc_returncode'] == '00'
        %w[pmtc_pay_with_reference pmtc_pay_with_recipientname pmtc_pay_with_amount pmtc_pay_with_iban].each do |field|
          if response[field].to_s.strip.empty?
            raise SveaPayments::InvalidResponseError, "Missing #{field}; request outcome may be unknown"
          end
        end
        # The funding amount need not equal the requested refund amount.
        amount = response['pmtc_pay_with_amount']
        unless amount.match?(/\A\d+,\d{2}\z/) && amount.delete(',').to_i.positive?
          raise SveaPayments::InvalidResponseError, 'Invalid funding amount; request outcome may be unknown'
        end
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

      final_payment_details = default_values.merge(payment_details.transform_keys(&:to_s))

      # Convert the final payment details hash to URL-encoded form data
      form_data = URI.encode_www_form(final_payment_details)
      
      xml_doc = send_post_request(uri, form_data, token)
      root = xml_doc.root
      errors = root.xpath('./errors/error | ./error').map(&:text)
      if errors.empty? && %w[pmt_id pmt_paymenturl].any? { |field| response_field(root, field).to_s.strip.empty? }
        invalid_response!('Missing payment result')
      end
      if final_payment_details.key?('pmt_id')
        validate_identity(root, { 'pmt_id' => final_payment_details['pmt_id'] }, required: errors.empty?)
      end
      # Convert XML document to a Ruby hash or handle it as needed
      # Example: extracting some fields
      response_data = {
        'pmt_id' => response_field(root, 'pmt_id').to_s,
        'pmt_reference' => response_field(root, 'pmt_reference').to_s,
        'pmt_amount' => response_field(root, 'pmt_amount').to_s,
        'pmt_currency' => response_field(root, 'pmt_currency').to_s,
        'pmt_sellercosts' => response_field(root, 'pmt_sellercosts').to_s,
        'pmt_paymentmethod' => response_field(root, 'pmt_paymentmethod').to_s,
        'pmt_paymenturl' => response_field(root, 'pmt_paymenturl').to_s,
        'errors' => errors
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
      root = xml_doc.root
      invalid_response!('Invalid payment query root') unless root.name == 'pmtq'
      code = response_field(root, 'pmtq_returncode')
      invalid_response!('Invalid payment query code') unless code&.match?(/\A\d{2}\z/)
      # Rejections may omit identifiers, but supplied identities must match.
      validate_identity(root, request_data.slice('pmtq_id', 'pmtq_sellerid'), required: code == '00')
      validate_identity(root, request_data.slice('pmtq_action', 'pmtq_version'), required: false)
      %w[
        pmtq_action pmtq_version pmtq_sellerid pmtq_id pmtq_orderid pmtq_amount
        pmtq_returncode pmtq_returntext pmtq_trackingcodes pmtq_sellercosts
        pmtq_invoicingfee pmtq_paymentmethod pmtq_escrow pmtq_certification
        pmtq_externalcode1 pmtq_externalcode2 pmtq_externaltext
        pmtq_paymentstarttimestamp pmtq_paymentdate pmtq_amountrefunded pmtq_payeriban
      ].to_h { |field| [field, response_field(root, field).to_s] }
    end
  end
end
