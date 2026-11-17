require_relative 'base'
require_relative 'signature'

module SveaPayments
  # Card tokenization and charging a saved card with its token. Requires a
  # separate agreement with Svea. Source: DOCS "Card (tokenization and
  # charging)" (page 1657013059, v13) and DOCSLEGACY "Hash Generation".
  #
  # Registration happens in the buyer's browser: build a form with
  # registration_form or payment_with_registration_form, submit it from the
  # browser, and pass the parameters of the buyer's return to verify_return to
  # obtain the token. Charging is server-to-server and never retried here.
  class CardToken
    extend Base

    PAYMENT_METHOD = 'FI50'
    REGISTRATION_VERSION = '4504'
    PAYMENT_WITH_REGISTRATION_VERSION = '4304'
    # PSD2 requires each charge to state who initiated it.
    CHARGE_VERSIONS = { customer: '4104', merchant: '4204' }.freeze
    ZERO_AMOUNT = '0,00'
    COMMA_AMOUNT = /\A\d+,\d{2}\z/
    # The provider asks for a later status query in these cases.
    UNKNOWN_ERROR_CODES = %w[ERROR_CARD_AUTHORIZATION_TIMEOUT WAITING ALREADY_PAID].freeze
    CHARGE_RESPONSE_FIELDS = %w[
      pmt_action pmt_version pmt_id pmt_reference pmt_amount pmt_currency
      pmt_sellercosts pmt_paymentmethod pmt_escrow pmt_resultcode
      pmt_cardholderauthenticationurl pmt_errorcode pmt_errortext
    ].freeze

    # Form for registering a card without a payment. The card is not charged.
    # Returns { 'url' => ..., 'fields' => { ... } } for a browser POST.
    def self.registration_form(details, secret:, hash_algorithm: 'SHA-512')
      fields = details.transform_keys(&:to_s)
      %w[pmt_amount pmt_sellercosts].each do |field|
        fields[field] = ZERO_AMOUNT if fields[field].to_s.strip.empty?
        raise ArgumentError, "#{field} must be #{ZERO_AMOUNT} when registering a card" unless fields[field] == ZERO_AMOUNT
      end
      fields = signed_fields(fields, secret, hash_algorithm,
        'pmt_action' => 'TOKENIZE', 'pmt_version' => REGISTRATION_VERSION)
      { 'url' => "#{SveaPayments.base_url}/TokenizeExtended.pmt", 'fields' => fields }
    end

    # Form for a card payment that also registers the card. The card is charged
    # only if the registration succeeds.
    def self.payment_with_registration_form(details, secret:, hash_algorithm: 'SHA-512')
      fields = details.transform_keys(&:to_s)
      require_amount!(fields, 'pmt_amount')
      fields = signed_fields(fields, secret, hash_algorithm,
        'pmt_action' => 'NEW_PAYMENT_EXTENDED', 'pmt_version' => PAYMENT_WITH_REGISTRATION_VERSION)
      { 'url' => "#{SveaPayments.base_url}/NewPaymentExtended.pmt", 'fields' => fields }
    end

    # Checks the parameters of the buyer's return to the OK address and returns
    # them, including 'pmt_token'. Raises InvalidResponseError unless the hash
    # is valid, the payment ID is the expected one and a token is present.
    # hash_algorithm must be the one used for the request.
    def self.verify_return(params, secret:, payment_id:, hash_algorithm: 'SHA-512')
      fields = params.to_h.transform_keys(&:to_s)
      result = (Signature::PAYMENT_RESPONSE_FIELDS + ['pmt_hash']).to_h { |name| [name, fields[name]] }
      unless result.values.all? { |value| value.nil? || value.is_a?(String) }
        raise SveaPayments::InvalidResponseError, 'Invalid card registration return'
      end
      expected = Signature.payment_response(result, secret, algorithm: hash_algorithm)
      unless Signature.match?(expected, result['pmt_hash'])
        raise SveaPayments::InvalidResponseError, 'Card registration return has an invalid hash'
      end
      unless result['pmt_id'] == payment_id.to_s && !payment_id.to_s.empty?
        raise SveaPayments::InvalidResponseError, 'Card registration return is for another payment'
      end
      if result['pmt_token'].to_s.strip.empty?
        raise SveaPayments::InvalidResponseError, 'Card registration return has no token'
      end
      result
    end

    # Charges a saved card. initiator is :customer (the cardholder is making a
    # purchase now) or :merchant (no cardholder present, including recurring).
    #
    # Returns the provider's fields plus 'errors' and 'outcome':
    #   'charged'                 - result code 00
    #   'authentication_required' - result code 01: redirect the cardholder to
    #                               'pmt_cardholderauthenticationurl'
    #   'unknown'                 - timed out, waiting or already paid: query the
    #                               payment status before doing anything else
    #   'failed'                  - refused; see 'pmt_errorcode' and 'errors'
    # Raised errors and timeouts also leave the outcome unknown. Never charge
    # again under a new payment ID before reconciling.
    def self.charge(token, details, secret:, initiator:, hash_algorithm: 'SHA-512')
      version = CHARGE_VERSIONS.fetch(initiator) do
        raise ArgumentError, 'initiator must be :customer or :merchant'
      end
      fields = details.transform_keys(&:to_s)
      %w[pmt_id pmt_token].each do |field|
        raise ArgumentError, "#{field} is required" if fields[field].to_s.strip.empty?
      end
      require_amount!(fields, 'pmt_amount')
      fields = signed_fields(fields, secret, hash_algorithm,
        'pmt_action' => 'NEW_PAYMENT_EXTENDED', 'pmt_version' => version)
      xml = send_post_request(
        URI("#{SveaPayments.charge_base_url}/NewChargeWithTokenExtended.pmt"),
        URI.encode_www_form(fields), token
      )
      parse_charge_response(xml.root, fields)
    end

    def self.require_amount!(fields, field)
      value = fields[field]
      return if value.is_a?(String) && value.match?(COMMA_AMOUNT)

      raise ArgumentError, "#{field} must be a string with two comma-separated decimals"
    end
    private_class_method :require_amount!

    # Protocol constants cannot be overridden by the caller.
    def self.signed_fields(fields, secret, hash_algorithm, constants)
      %w[pmt_charset pmt_charsethttp].each do |field|
        unless [nil, Signature::CHARSET].include?(fields[field])
          raise ArgumentError, "#{field} must be #{Signature::CHARSET}"
        end
      end
      fields = { 'pmt_keygeneration' => '001' }.merge(fields).merge(constants).merge(
        'pmt_paymentmethod' => PAYMENT_METHOD, 'pmt_charset' => Signature::CHARSET,
        'pmt_charsethttp' => Signature::CHARSET, 'pmt_hashversion' => hash_algorithm
      )
      fields.delete('pmt_hash')
      fields.merge('pmt_hash' => Signature.payment_request(fields, secret, algorithm: hash_algorithm))
    end
    private_class_method :signed_fields

    def self.parse_charge_response(root, request)
      invalid_response!('Invalid token charge root') unless root.name == 'chargeWithTokenResponse'
      response = CHARGE_RESPONSE_FIELDS.to_h { |field| [field, response_field(root, field)] }
      response['errors'] = root.xpath('./error | ./errors/error').map do |error|
        { 'type' => error['type'], 'name' => error['name'], 'message' => error.text }
      end
      code = response['pmt_resultcode']
      invalid_response!('Invalid token charge result code') unless code.nil? || code.match?(/\A\d{2}\z/)
      if code.nil? && response['pmt_errorcode'].to_s.strip.empty? && response['errors'].empty?
        invalid_response!('Missing token charge result')
      end
      validate_identity(root, request.slice('pmt_id'), required: %w[00 01].include?(code))
      response['outcome'] = charge_outcome(response)
      response
    end
    private_class_method :parse_charge_response

    def self.charge_outcome(response)
      error_code = response['pmt_errorcode'].to_s.strip
      return 'unknown' if UNKNOWN_ERROR_CODES.include?(error_code)

      case response['pmt_resultcode']
      when '00'
        invalid_response!('Token charge reports both success and an error') unless error_code.empty?
        'charged'
      when '01'
        unless response['pmt_cardholderauthenticationurl'].to_s.match?(%r{\Ahttps://\S+\z})
          invalid_response!('Missing cardholder authentication URL')
        end
        'authentication_required'
      when '99' then 'failed'
      # An undocumented result code is not evidence of success or refusal.
      else error_code.empty? && response['errors'].empty? ? 'unknown' : 'failed'
      end
    end
    private_class_method :charge_outcome
  end
end
