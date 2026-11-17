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

### Saved cards: registering and charging with a token

Requires a separate agreement with Svea. Svea's card processor stores the card;
your application stores only the token. Nothing here has been run against
Svea: it follows the documentation, and the points marked **unverified** below
need a sandbox check before use.

The [saved cards integration guide](docs/saved-cards.md) describes the ways to
use this (subscriptions, card on file, one-click purchases, varying merchant
charges, replacing a card) and the full sequence for each.

**1. Register the card (in the buyer's browser).** The buyer must have accepted
that the card is stored. Build a form and submit it from the browser:

```ruby
form = SveaPayments::CardToken.registration_form({
  'pmt_sellerid' => seller_id, 'pmt_id' => 'unique-id', 'pmt_orderid' => 'order-1',
  'pmt_reference' => '19985242', 'pmt_currency' => 'EUR',
  'pmt_okreturn' => 'https://shop.example/cards/return', # plus the other
  # fields Svea requires for a payment: error/cancel URLs, buyer and row fields
}, secret: secret_key)
form['url']    # => ".../TokenizeExtended.pmt"
form['fields'] # => hidden inputs, including pmt_hash
```

`registration_form` registers without charging (amounts are `0,00`).
`payment_with_registration_form` charges the card and registers it in one step.
Both set payment method `FI50`, UTF-8 and the request hash; the caller cannot
override those. The secret key is used for the hash and never placed in the form.

**2. Read the token from the buyer's return.**

```ruby
result = SveaPayments::CardToken.verify_return(request_params, secret: secret_key, payment_id: 'unique-id')
result['pmt_token'] # store against the customer who registered the card
```

It raises `SveaPayments::InvalidResponseError` unless the hash is valid, the
payment ID is the one you expect and a token is present. Make sure the return
belongs to the signed-in customer before storing the token. The token is also
returned as `pmtq_token` by `query_payment_status`, along with its expiry,
limits and masked card details.

**3. Charge the card (server to server).**

```ruby
result = SveaPayments::CardToken.charge(token, {
  'pmt_sellerid' => seller_id, 'pmt_id' => 'unique-charge-id', 'pmt_token' => card_token,
  'pmt_amount' => '50,00', 'pmt_sellercosts' => '0,00', 'pmt_currency' => 'EUR',
  # plus the other fields Svea requires for a payment, including return URLs
}, secret: secret_key, initiator: :customer)
```

`initiator` is required: `:customer` when the cardholder is making a purchase
now, `:merchant` when no cardholder is present, including recurring charges.
`token` is the Basic authentication value; `secret` signs the request.

| `outcome` | Meaning | What to do |
| --- | --- | --- |
| `charged` | Result code `00` | Fulfil the order |
| `authentication_required` | Result code `01` (customer-initiated only) | Redirect the cardholder to `pmt_cardholderauthenticationurl`; the charge completes, or not, when they return to your OK, cancel or error URL |
| `unknown` | Timed out, waiting, already paid, or an undocumented result | Query the payment status; do not charge again |
| `failed` | Refused | See `pmt_errorcode`, `pmt_errortext` and `errors` |

`HTTPError`, `InvalidResponseError` and timeouts also leave the outcome
unknown. Persist the `pmt_id` before calling, never retry under a new ID before
`query_payment_status` has settled the old one, and treat only a confirmed
status as paid. Charges are never retried by the gem.

Svea's rules for merchant-initiated and recurring charges are yours to meet:
the cardholder accepts the recurring terms before registration, receives a
confirmation, is told the amount and date before each charge, and can cancel.
Svea blocks charges beyond the agreed monthly amount or count, and states that
a recurring charge cannot exceed the original payment.

**Unverified against Svea:**

- The hash format has no reproducible test vector; the documentation's example
  hashes do not publish their secret key.
- The charge reply's `pmt_hash` is not checked, because the documentation does
  not list its fields.
- Whether the registration endpoints also accept the server-to-server request
  with Basic authentication used by `create_payment`.
- The documentation lists `http://test1.maksuturva.fi` for these endpoints; the
  gem uses `https://test1.maksuturva.fi`.
- The token information endpoint (`/api/token-query/`) is not implemented: its
  URL format is ambiguous in the documentation.
- Token deletion is not documented and not implemented.

Source: [Card (tokenization and charging)](https://sveapayments.atlassian.net/wiki/spaces/DOCS/pages/1657013059)
and [Hash Generation](https://sveapayments.atlassian.net/wiki/spaces/DOCSLEGACY/pages/262253).

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
