# SveaPayments

SveaPayments is a Ruby gem for integrating with the Svea Payments API. This gem provides methods for creating payments and querying payment statuses.

## Installation

Requires Ruby 3.2 or later. CI tests Ruby 3.2 and the consumer's Ruby 3.4.9.

**Upgrading to 0.2.0:** operations now raise on HTTP errors, malformed replies,
failed status queries and failed report requests instead of returning empty
data. Read [Response handling in 0.2.0](#response-handling-in-020) before upgrading.

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

### Refund Before Settlement

Use this while the payment has not reached settlement. It asks Svea to refund
the buyer in full or in part; no merchant bank transfer is involved.

```ruby
refund = SveaPayments::Payment.refund_before_settlement(token, {
  'pmtc_sellerid' => 'your_seller_id',
  'pmtc_id' => 'original_payment_id',
  'pmtc_amount' => '100,00',            # Original pmt_amount
  'pmtc_currency' => 'EUR',            # Original pmt_currency
  'pmtc_canceltype' => 'PARTIAL_REFUND',
  'pmtc_cancelamount' => '15,00',       # Partial refunds only
  'pmtc_cancel_id' => 'order-123-refund-1' # Persist this unique refund ID
})
```

`pmtc_canceltype` is `FULL_REFUND`, `PARTIAL_REFUND` or
`PARTIAL_REFUND_AND_RETURN_OF_DELIVERIES`. Omit `pmtc_cancelamount` for
`FULL_REFUND` (Svea requires this; supplying it raises `ArgumentError`) and
supply a positive amount for the partial types. The method supplies action
`CANCEL`, version `0005`, XML response type and key generation `001`.

| `pmtc_returncode` | Meaning |
| --- | --- |
| `00` | Cancel received successfully |
| `20` | Payment not found |
| `30` | Already settled; use `refund_after_settlement` instead |
| `31` | Seller and buyer cancellation parameters do not match |
| `90` | Invalid input; inspect `errors` |
| `91` | Duplicate `pmtc_cancel_id` for this order; not a new accepted refund |
| `99` | Failed; inspect `pmtc_returntext` |

The result contains `pmtc_action`, `pmtc_version`, `pmtc_sellerid`, `pmtc_id`,
`pmtc_returncode`, `pmtc_returntext` and `errors`. Code `30` is returned, never
followed automatically by an after-settlement request: that path needs a
merchant bank transfer, so the caller must choose it. Optional request fields,
error classes, timeouts and the no-retry rule are the same as for
after-settlement refunds below. Svea's optional change rows
(`pmtc_refund_quantity_of_original_rowN`, `pmtc_additional_row_*`) are passed
through unvalidated.

Source: [Refund or Cancel Payment](https://sveapayments.atlassian.net/wiki/spaces/DOCS/pages/1657012799).

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
This document specifies **no grace-period cutoff**. Refund-completion polling is
not implemented.

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

The XML result is a hash with `resultCode`, `resultText` and `compensations`
(each with its `orders`). Svea's result codes are `00` success, `91` service not
available for the seller, `95` errors in the request and `99` error. Any code
other than `00` raises `SveaPayments::ReportError` (with `code` and `text`), so
a failed request cannot be mistaken for an empty report. The one exception is
Svea's documented reply for a period without settlements, `95` with the text
`No events found.`, which returns an empty `compensations` array. The interval
may be at most one month and must not include today or future dates. CSV is
returned as the raw response string and is not checked for result codes.

Source: [Report Request](https://sveapayments.atlassian.net/wiki/spaces/DOCS/pages/1657012958)
and `GetCompensationsResponse.xsd`.

## Development

### Response handling in 0.2.0

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
  record, never a nested order. Missing amounts remain `nil`. A report result
  code other than `00` raises `SveaPayments::ReportError`, except the documented
  empty-period reply.
- Payment-method replies must be a `paymentmethods` list with nonempty method
  codes. Error/unrecognized XML is rejected, not treated as an empty list.

Consumers must rescue transport/response exceptions where they previously
checked empty values. Preserve existing payment IDs on failure; do not mark an
outage as an empty settlement report. Reconcile uncertain create/refund outcomes
before retrying. No application integration changes are included in this gem.

Report, refund and status-query parsing follow the examples and tables in
Svea's public documentation; see [docs/provider-contract-sources.md](docs/provider-contract-sources.md).
The remaining offline fixtures are synthetic regression examples, not captured
provider responses, and nothing here has been run against Svea's sandbox or
production for 0.2.0.

`bundle exec rake` runs offline tests only. Tests tagged `live` contact Svea's
sandbox and can create payments. Run them deliberately with
`SVEA_LIVE_TESTS=1 bundle exec rspec spec/integration`.
Live networking is restricted to HTTPS on `test1.maksuturva.fi`.


After checking out the repo, run bin/setup to install dependencies. Then, run rake spec to run the tests. You can also run bin/console for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run bundle exec rake install. To release a new version, update the version number in version.rb, and then run bundle exec rake release, which will create a git tag for the version, push git commits and the created tag, and push the .gem file to rubygems.org.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/akonan/svea_payments.

## License

The gem is available as open source under the terms of the MIT License. 
