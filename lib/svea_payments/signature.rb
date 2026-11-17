require 'digest'
require 'openssl'

module SveaPayments
  # Hash calculation for Svea's hash-signed (V4) messages, which the card
  # tokenization interface uses. Values are joined in the documented order,
  # each followed by "&", ending with the secret key and a final "&". Blank
  # values are left out together with their "&".
  # Source: DOCSLEGACY "Hash Generation" (page 262253).
  module Signature
    ALGORITHMS = { 'SHA-512' => Digest::SHA512, 'SHA-256' => Digest::SHA256 }.freeze
    CHARSET = 'UTF-8'

    PAYMENT_REQUEST_FIELDS = %w[
      pmt_action pmt_version pmt_id pmt_orderid pmt_reference pmt_duedate pmt_amount
      pmt_currency pmt_okreturn pmt_errorreturn pmt_cancelreturn pmt_delayedpayreturn
      pmt_escrow pmt_escrowchangeallowed pmt_invoicefromseller pmt_paymentmethod
      pmt_buyeridentificationcode pmt_buyername pmt_buyeraddress pmt_buyerpostalcode
      pmt_buyercity pmt_buyercountry pmt_deliveryname pmt_deliveryaddress
      pmt_deliverypostalcode pmt_deliverycity pmt_deliverycountry pmt_sellercosts
      pmt_token pmt_marketplacecommission pmt_marketplacereference
    ].freeze
    PAYMENT_ROW_FIELDS = %w[
      pmt_row_name pmt_row_desc pmt_row_quantity pmt_row_articlenr pmt_row_unit
      pmt_row_deliverydate pmt_row_price_gross pmt_row_price_net pmt_row_vat
      pmt_row_discountpercentage pmt_row_type
    ].freeze
    PAYMENT_RESPONSE_FIELDS = %w[
      pmt_action pmt_version pmt_id pmt_reference pmt_amount pmt_currency
      pmt_sellercosts pmt_paymentmethod pmt_escrow pmt_token
    ].freeze
    STATUS_QUERY_RESPONSE_FIELDS = %w[
      pmtq_action pmtq_version pmtq_sellerid pmtq_id pmtq_amount pmtq_returncode
      pmtq_returntext pmtq_sellercosts pmtq_paymentmethod pmtq_escrow
      pmtq_certification pmtq_paymentdate pmtq_token
    ].freeze

    class << self
      # Upper-case hex digest of the ordered values and the secret key.
      def digest(values, secret, algorithm: 'SHA-512')
        raise ArgumentError, 'secret is required' if secret.to_s.empty?

        digest_class = ALGORITHMS.fetch(algorithm) do
          raise ArgumentError, "hash algorithm must be one of #{ALGORITHMS.keys.join(', ')}"
        end
        parts = values.map(&:to_s).reject(&:empty?) << secret.to_s
        digest_class.hexdigest(parts.map { |part| "#{part}&" }.join.encode(CHARSET)).upcase
      end

      # Hash of a new payment, tokenization or token charge request.
      def payment_request(fields, secret, algorithm: 'SHA-512')
        fields = fields.transform_keys(&:to_s)
        values = PAYMENT_REQUEST_FIELDS.map { |name| fields[name] }
        (1..fields['pmt_rows'].to_i).each do |row|
          values.concat(PAYMENT_ROW_FIELDS.map { |name| fields["#{name}#{row}"] })
        end
        digest(values, secret, algorithm: algorithm)
      end

      # Hash Svea sends with the buyer's return to the OK address.
      def payment_response(fields, secret, algorithm: 'SHA-512')
        response_digest(PAYMENT_RESPONSE_FIELDS, fields, secret, algorithm)
      end

      # Hash of a payment status query reply (pmtq_hash).
      def status_query_response(fields, secret, algorithm: 'SHA-512')
        response_digest(STATUS_QUERY_RESPONSE_FIELDS, fields, secret, algorithm)
      end

      # Constant-time comparison; Svea sends upper case but either case is legal.
      def match?(expected, actual)
        expected = expected.to_s.upcase
        actual = actual.to_s.upcase
        return false if expected.empty? || expected.bytesize != actual.bytesize

        OpenSSL.fixed_length_secure_compare(expected, actual)
      end

      private

      def response_digest(names, fields, secret, algorithm)
        fields = fields.transform_keys(&:to_s)
        digest(names.map { |name| fields[name] }, secret, algorithm: algorithm)
      end
    end
  end
end
