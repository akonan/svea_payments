# SveaPayments

SveaPayments is a Ruby gem for integrating with the Svea Payments API. This gem provides methods for creating payments and querying payment statuses.

## Installation

Requires Ruby 3.2 or later. CI tests Ruby 3.2 and the consumer's Ruby 3.4.9.

**Release hold:** the unreleased refund work is not approved for a public gem
release. The remaining codebase-review findings must be resolved separately.

To install the gem and add it to your application's Gemfile, execute:

    $ bundle add svea_payments

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install svea_payments

## Configuration

Before using the gem, you need to configure it to use either the test or production environment. By default, the gem uses the production environment.

To configure the gem, add the following code to your application:

SveaPayments.configure do |config|
  config.use_test_env = true # default is false
end

## Usage

Refer to the Svea Payments API documentation and this gem's tests: https://sveapayments.atlassian.net/wiki/spaces/DOCS/overview?homepageId=65539
### Authentication

First, obtain an authentication token. The returned string can be used as the
value for the `Authorization` HTTP header:

    token = SveaPayments::Authentication.get_basic_auth_token(username, password)

### Creating a Payment

To create a payment, provide the necessary payment details in this style:

    payment_details = {
      'pmt_reference' => 'your_reference',
      'pmt_amount' => '1000',
      'pmt_currency' => 'EUR',
      'pmt_sellercosts' => '0',
      'pmt_paymentmethod' => 'creditcard'
    }

    payment_response = SveaPayments::Payment.create_payment(token, payment_details)

### Querying Payment Status

To query the status of a payment, use the payment ID:

    payment_status = SveaPayments::Payment.query_payment_status(token, payment_response['pmt_id'], pmt_sellerid)

### Refund After Settlement

Use this only after Svea has settled the original payment to the merchant.
It **initiates** a refund; it does not transfer money or confirm the buyer has
received it.

```ruby
refund = SveaPayments::Payment.refund_after_settlement(token, {
  'pmtc_sellerid' => 'your_seller_id',
  'pmtc_id' => 'original_payment_id',
  'pmtc_amount' => '100,00',       # Original pmt_amount, NOT the refund amount
  'pmtc_currency' => 'EUR',       # Original pmt_currency
  'pmtc_cancelamount' => '15,00',  # Full or partial amount to refund
  'pmtc_cancel_id' => 'order-123-refund-1' # Persist this unique refund ID
})
```

Amounts must be strings with two decimal places and a comma, without thousands
separators. The method supplies action/canceltype `REFUND_AFTER_SETTLEMENT`,
version `0005`, XML response type and key generation `001`. Override only key
generation when necessary using `pmtc_keygeneration`.

| `pmtc_returncode` | Meaning |
| --- | --- |
| `00` | Request received successfully; **merchant funding still required** |
| `20` | Payment not found |
| `90` | Invalid input; inspect `errors` |
| `91` | Duplicate `pmtc_cancel_id` for this order; not a new accepted refund |
| `99` | Failed; inspect `pmtc_returntext` |

The result is a string-keyed hash preserving the provider's response fields.
On `00`, use `pmtc_pay_with_iban`, `pmtc_pay_with_recipientname`,
`pmtc_pay_with_amount` and `pmtc_pay_with_reference` to **separately transfer
money from the merchant's bank to Svea**. Use the exact returned amount and
reference (including leading zeroes); do not substitute the requested amount.
Svea refunds the buyer after receiving the merchant's money. This gem does not
perform that bank transfer. Confirm all instructions are present before acting.

`errors` is an array of hashes with `type`, `name` and `message`; absent response
fields are `nil`. Unknown return codes are preserved, not interpreted as success.
`pmtc_returntext` is preserved even for `00`: the PDF's example contains success
text despite its field table saying the success text is empty.

Optional request fields: `pmtc_canceldescription` (up to 500 characters),
`pmtc_cancelreason` (`NOTDE`, `WSIZE`, `INCOR`, `DEFEC`, `OUTOF`, `OTHER`),
`pmtc_payeribanrefund` (Finnish buyer IBAN, only for applicable bank payments),
and `pmtc_pay_with_reference` (requires a separate agreement with Svea).
Provider-specific eligibility and optional-field validation remain with Svea.

Use a stable `pmtc_cancel_id` for each logical refund. The provider rejects reuse
for another refund on the same order. A timeout or HTTP error can leave the
outcome unknown: reconcile before retrying, and never generate a new ID merely
to bypass a duplicate response. This method never retries automatically.

Non-2xx HTTP responses raise `SveaPayments::HTTPError` (with `status`); malformed
XML or a missing refund root/code raises `SveaPayments::InvalidResponseError`.
Network errors propagate. All requests use 10-second connect and 30-second
read/write timeouts and disable automatic retries.

Source: [Refund Payment After Settlement](https://sveapayments.atlassian.net/wiki/spaces/DOCS/pages/1657012824),
provided PDF export `DOCS-Refund Payment After Settlement-210926-133729.pdf`.
This document specifies **no grace-period cutoff**. Before-settlement cancellation
and refund-completion polling are not implemented by this method.

### Getting Available Payment Methods

    request_details = {
    'sellerid' => 'seller_id',
    'request_locale' => 'fi',
    'totalamount' => '47,50'
    }

    SveaPayments::PaymentMethods.get_available_payment_methods(token, request_details)

### Compensation report query

    start_date = Date.new(2024, 11, 1)
    end_date = Date.new(2024, 11, 30)
    SveaPayments::Reports.get_compensation_report(start_date, end_date, seller_id, token)
    SveaPayments::Reports.get_compensation_report(start_date, end_date, seller_id, token, format: 'CSV', key_generation: '004')

## Development

### Response-handling compatibility changes (unreleased)

- Every operation now raises `SveaPayments::HTTPError` on non-2xx responses,
  including redirects, instead of returning empty payment/report/method data.
  The error exposes `status`; response bodies and credentials are not logged.
- Invalid XML, missing required result fields and ambiguous scalar fields raise
  `SveaPayments::InvalidResponseError`. Confirmed payment query codes (20–98)
  must echo the requested payment and seller IDs. Non-confirmed/cancelled replies
  may omit those IDs, but supplied IDs must match. Code 00 means unpaid, not paid.
  Code 01 means the query failed and raises `SveaPayments::Error`; never treat it
  as proof of nonpayment. Other codes/text remain available in the result hash.
  See [the provider-sourced query contract](docs/query-status-contract.md).
- Create-payment business errors remain an array of strings. An error-free
  create result must contain a payment ID and payment URL; the ID must match
  the submitted ID when one was supplied.
- CSV reports now return the exact response `String`, not a Nokogiri document.
  Only the exact format strings `XML` and `CSV` are supported; other values raise
  `ArgumentError` before sending. XML report scalar values come from their own
  record, never a nested order. Missing amounts remain `nil`.
- Payment-method replies must be a `paymentmethods` list with nonempty method
  codes. Error/unrecognized XML is rejected, not treated as an empty list.

Consumers must rescue transport/response exceptions where they previously
checked empty values. Preserve existing payment IDs on failure; do not mark an
outage as an empty settlement report. Reconcile uncertain create/refund outcomes
before retrying. No application integration changes are included in this gem.

The offline XML fixtures are synthetic regression examples based on the gem's
existing fields, not captured provider responses. They do not establish every
live XML wrapper or business-error variant. Validate against documentation
exports or redacted provider fixtures before deploying the stricter parsers.
The public release hold remains in effect.

`bundle exec rake` runs offline tests only. Tests tagged `live` contact Svea's
sandbox and can create payments. Run them deliberately with
`SVEA_LIVE_TESTS=1 bundle exec rspec spec/integration`.
Live networking is restricted to HTTPS on `test1.maksuturva.fi`.


After checking out the repo, run bin/setup to install dependencies. Then, run rake spec to run the tests. You can also run bin/console for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run bundle exec rake install. To release a new version, update the version number in version.rb, and then run bundle exec rake release, which will create a git tag for the version, push git commits and the created tag, and push the .gem file to rubygems.org.

## TODO

- Before-settlement cancellation/refunds (requires the separate API contract)

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/akonan/svea_payments.

## License

The gem is available as open source under the terms of the MIT License. 
