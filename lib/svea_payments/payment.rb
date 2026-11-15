require_relative 'base'

module SveaPayments
  class Payment
    extend Base
    REFUND_RESPONSE_FIELDS = %w[
      pmtc_action pmtc_version pmtc_sellerid pmtc_id pmtc_returncode
      pmtc_returntext pmtc_pay_with_reference pmtc_pay_with_recipientname
      pmtc_pay_with_amount pmtc_pay_with_iban
    ].freeze

    CANCEL_RESPONSE_FIELDS = %w[
      pmtc_action pmtc_version pmtc_sellerid pmtc_id pmtc_returncode pmtc_returntext
    ].freeze
    BEFORE_SETTLEMENT_CANCEL_TYPES = %w[
      FULL_REFUND PARTIAL_REFUND PARTIAL_REFUND_AND_RETURN_OF_DELIVERIES
    ].freeze
    COMMA_AMOUNT = /\A\d+,\d{2}\z/

    # Refunds or cancels a payment that has not reached settlement. Code 00 means
    # the request was received. Code 30 means the payment is already settled:
    # the caller decides whether to use refund_after_settlement; nothing falls
    # back automatically and nothing is retried.
    def self.refund_before_settlement(token, refund_details)
      details = refund_details.transform_keys(&:to_s)
      require_cancel_fields!(details, %w[pmtc_sellerid pmtc_id pmtc_amount pmtc_currency pmtc_canceltype])
      require_comma_amount!(details, 'pmtc_amount')
      type = details['pmtc_canceltype']
      unless BEFORE_SETTLEMENT_CANCEL_TYPES.include?(type)
        raise ArgumentError, "pmtc_canceltype must be one of #{BEFORE_SETTLEMENT_CANCEL_TYPES.join(', ')}"
      end
      if type == 'FULL_REFUND'
        # The provider requires the amount to be omitted for a full refund.
        unless details['pmtc_cancelamount'].to_s.strip.empty?
          raise ArgumentError, 'pmtc_cancelamount must be omitted for FULL_REFUND'
        end
        details.delete('pmtc_cancelamount')
      else
        require_cancel_fields!(details, %w[pmtc_cancelamount])
        require_comma_amount!(details, 'pmtc_cancelamount')
        unless details['pmtc_cancelamount'].delete(',').to_i.positive?
          raise ArgumentError, 'pmtc_cancelamount must be greater than zero'
        end
      end
      request = { 'pmtc_keygeneration' => '001' }.merge(details).merge(
        'pmtc_action' => 'CANCEL', 'pmtc_version' => '0005', 'pmtc_resptype' => 'XML'
      )
      _root, response = post_cancel(token, request, CANCEL_RESPONSE_FIELDS)
      response
    end

    # Initiates a refund only. The merchant must separately fund it using the
    # returned bank transfer instructions. No money transfer or retry is done here.
    def self.refund_after_settlement(token, refund_details)
      details = refund_details.transform_keys(&:to_s)
      require_cancel_fields!(details, %w[pmtc_sellerid pmtc_id pmtc_amount pmtc_currency pmtc_cancelamount])
      %w[pmtc_amount pmtc_cancelamount].each { |field| require_comma_amount!(details, field) }
      # Protocol constants cannot be overridden by the caller.
      request = { 'pmtc_keygeneration' => '001' }.merge(details).merge(
        'pmtc_action' => 'REFUND_AFTER_SETTLEMENT',
        'pmtc_version' => '0005',
        'pmtc_canceltype' => 'REFUND_AFTER_SETTLEMENT',
        'pmtc_resptype' => 'XML'
      )
      _root, response = post_cancel(token, request, REFUND_RESPONSE_FIELDS)
      if response['pmtc_returncode'] == '00'
        %w[pmtc_pay_with_reference pmtc_pay_with_recipientname pmtc_pay_with_amount pmtc_pay_with_iban].each do |field|
          if response[field].to_s.strip.empty?
            raise SveaPayments::InvalidResponseError, "Missing #{field}; request outcome may be unknown"
          end
        end
        # The funding amount need not equal the requested refund amount.
        amount = response['pmtc_pay_with_amount']
        unless amount.match?(COMMA_AMOUNT) && amount.delete(',').to_i.positive?
          raise SveaPayments::InvalidResponseError, 'Invalid funding amount; request outcome may be unknown'
        end
      end
      response
    end

    def self.require_cancel_fields!(details, fields)
      fields.each do |field|
        raise ArgumentError, "#{field} is required" if details[field].to_s.strip.empty?
      end
    end
    private_class_method :require_cancel_fields!

    def self.require_comma_amount!(details, field)
      value = details[field]
      return if value.is_a?(String) && value.match?(COMMA_AMOUNT)

      raise ArgumentError, "#{field} must be a string with two comma-separated decimals"
    end
    private_class_method :require_comma_amount!

    # Shared PaymentCancel.pmt exchange: one request, never retried. The reply
    # must echo the request's action, version, seller and payment identity.
    def self.post_cancel(token, request, fields)
      xml = send_post_request(
        URI("#{SveaPayments.base_url}/PaymentCancel.pmt"),
        URI.encode_www_form(request), token
      )
      root = xml.root
      if !root || root.name != 'pmtc' || root.at_xpath('./pmtc_returncode')&.text.to_s.empty?
        raise SveaPayments::InvalidResponseError, 'Missing refund response/code; request outcome may be unknown'
      end
      response = fields.each_with_object({}) do |field, result|
        result[field] = root.at_xpath("./#{field}")&.text
      end
      # Reject ambiguous replies instead of choosing the first duplicate field.
      fields.each do |field|
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
      response['errors'] = root.xpath('./errors/error').map do |error|
        { 'type' => error['type'], 'name' => error['name'], 'message' => error.text }
      end
      [root, response]
    end
    private_class_method :post_cancel

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
      # Query codes are NOT refund codes: 00 is unpaid, 20–98 is confirmed,
      # 99 is cancelled/refunded, and 01 means the query itself failed.
      # See docs/query-status-contract.md for the provider source.
      if code == '01'
        raise SveaPayments::Error, 'Payment status query failed (01); payment outcome remains unknown'
      end
      validate_identity(root, request_data.slice('pmtq_id', 'pmtq_sellerid'), required: code.to_i.between?(20, 98))
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
