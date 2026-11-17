# Saved cards: integration guide

**Status: unverified.** This guide follows Svea's documentation. Nothing in it
has been run against Svea's test or production service. Treat the first sandbox
run as the real test of every step, and see [Not yet verified](#not-yet-verified).

Saved cards need a separate agreement with Svea. Svea's card processor stores
the card. Your application stores only the token Svea returns.

Sources: [Card (tokenization and charging)](https://sveapayments.atlassian.net/wiki/spaces/DOCS/pages/1657013059)
and [Hash Generation](https://sveapayments.atlassian.net/wiki/spaces/DOCSLEGACY/pages/262253).

## The building blocks

| Call | Where it runs | What it does |
| --- | --- | --- |
| `CardToken.registration_form` | Buyer's browser posts the form | Saves a card without charging it |
| `CardToken.payment_with_registration_form` | Buyer's browser posts the form | Charges the card and saves it |
| `CardToken.verify_return` | Your server, on the buyer's return | Checks the return and gives you the token |
| `CardToken.charge` | Your server | Charges a saved card |
| `Payment.query_payment_status` | Your server | Settles an uncertain charge; also returns the token and card details |

Two credentials are involved. `secret` signs the forms and charge requests and
checks the buyer's return. `token` (the first argument of `charge` and
`query_payment_status`) is the Basic authentication value from
`SveaPayments::Authentication`.

## Choosing a way to use it

| You want to | Registration | Later charges | Section |
| --- | --- | --- | --- |
| Sell a subscription that starts with a payment | Payment and registration | `:merchant`, same amount each period | [A](#a-subscription-that-starts-with-a-payment) |
| Start a trial, or let a customer add a card to their account | Registration only | `:merchant` or `:customer` | [B](#b-card-on-file-without-a-first-payment) |
| Let a returning customer pay in one click | Either | `:customer` | [C](#c-one-click-purchase) |
| Bill varying amounts after the fact (usage, a no-show fee) | Either | `:merchant` | [D](#d-merchant-charges-of-varying-amounts) |
| Replace an expiring or lost card | Registration only | Unchanged | [E](#e-replacing-a-card) |

All of them share the same three steps: [register](#registering-a-card),
[read the token](#reading-the-token), [charge](#charging-a-saved-card).

### A. Subscription that starts with a payment

1. Show the recurring terms (amount, interval, validity, how to cancel) and
   record the cardholder's acceptance.
2. Post `payment_with_registration_form` with the first period's amount.
3. On return, call `verify_return` and store the token.
4. Send the confirmation email Svea requires (see [Svea's rules](#sveas-rules-for-recurring-charges)).
5. Before each renewal, tell the cardholder the amount and date, then call
   `charge` with `initiator: :merchant`.

This is the pattern Svea's documentation describes most fully. The first
payment sets the "original payment" amount, and Svea states that a recurring
charge cannot exceed it.

### B. Card on file without a first payment

1. Tell the cardholder the card will be stored and record their acceptance. If
   it will be charged automatically, show the recurring terms as in A.
2. Post `registration_form`. The card is not charged.
3. On return, call `verify_return` and store the token.
4. Charge later with `initiator: :merchant` (trial ends, renewal) or
   `initiator: :customer` (the cardholder buys something).

Open question for Svea: with no first payment there is no "original payment",
so it is unclear which amount later recurring charges are measured against.
Ask before relying on this pattern for subscriptions.

### C. One-click purchase

The cardholder is present and buying now. Call `charge` with
`initiator: :customer`. Svea requires this initiator to be stated truthfully on
every charge.

Only this pattern can return `authentication_required`. When it does:

1. Redirect the cardholder to `pmt_cardholderauthenticationurl`.
2. Svea charges the card after a successful authentication and sends the
   cardholder to the OK address from your charge request. Otherwise they arrive
   at the cancel or error address.
3. Do not fulfil the order on the return alone. Confirm with
   `query_payment_status`.

Your charge request must therefore carry working OK, cancel and error
addresses, and the purchase must be able to wait in a pending state.

### D. Merchant charges of varying amounts

For amounts that are not a fixed recurring fee, for example usage billed
afterwards. Call `charge` with `initiator: :merchant`. No cardholder is
present, so there is no authentication step: Svea's documentation says such a
charge is usually either accepted or not.

Svea blocks charges that exceed the monthly amount or count agreed for the
seller, and in principle allows one recurring charge per month. Confirm the
limits in your agreement before building on this pattern. The token's own limits
are returned by `query_payment_status` (`pmtq_token_debit_limit`,
`pmtq_token_debit_limit_monthly`).

### E. Replacing a card

Run registration again (pattern B) under a new payment ID. Swap the stored
token only after `verify_return` succeeds for the new one, so a failed or
abandoned attempt leaves the old card usable. Deleting the old token at Svea is
not documented; discard it locally.

## Registering a card

Registration happens in the cardholder's browser, where the card processor
also runs 3-D Secure authentication.

```ruby
form = SveaPayments::CardToken.registration_form({
  'pmt_sellerid' => seller_id, 'pmt_id' => payment_id, 'pmt_orderid' => order_id,
  'pmt_reference' => reference, 'pmt_currency' => 'EUR',
  'pmt_okreturn' => 'https://shop.example/cards/return',
  # plus the other fields Svea requires for a payment:
  # error and cancel addresses, buyer fields and row fields
}, secret: secret_key)
```

Render `form['fields']` as hidden inputs in a form that posts to `form['url']`:

```erb
<form action="<%= form['url'] %>" method="post" accept-charset="UTF-8">
  <% form['fields'].each do |name, value| %>
    <input type="hidden" name="<%= name %>" value="<%= value %>">
  <% end %>
  <button type="submit">Save card</button>
</form>
```

`payment_with_registration_form` takes the same fields with real amounts
(`'pmt_amount' => '29,00'`, two decimals, comma separator).

Before rendering the form, save a local record holding `payment_id` and the
customer it belongs to. You need both on the return.

## Reading the token

```ruby
result = SveaPayments::CardToken.verify_return(
  request_params, secret: secret_key, payment_id: expected_payment_id
)
card_token = result['pmt_token']
```

`verify_return` raises `SveaPayments::InvalidResponseError` unless the hash is
valid, the payment ID is the one you pass and a token is present. Two checks
remain yours:

- Take `expected_payment_id` from your own record, never from the request.
- Confirm the record belongs to the signed-in customer before storing the token.

If the cardholder closes the browser before returning, the token is not lost:
`query_payment_status` for the same payment ID returns it as `pmtq_token`.
A scheduled job can recover registrations that never returned.

Store against the customer: the token, `pmtq_token_expiration_month` and
`pmtq_token_expiration_year`, `pmtq_card_number_masked`, `pmtq_card_scheme` and
the record of what the cardholder accepted. Treat the token as a credential:
encrypt it at rest and keep it out of logs.

## Charging a saved card

```ruby
result = SveaPayments::CardToken.charge(token, {
  'pmt_sellerid' => seller_id, 'pmt_id' => charge_id, 'pmt_token' => card_token,
  'pmt_amount' => '29,00', 'pmt_sellercosts' => '0,00', 'pmt_currency' => 'EUR',
  # plus the other fields Svea requires for a payment, including return addresses
}, secret: secret_key, initiator: :merchant)
```

Save the charge record with its `charge_id` before the call, then act on
`result['outcome']`:

| Outcome | Meaning | What to do |
| --- | --- | --- |
| `charged` | Svea accepted the charge | Mark paid |
| `authentication_required` | The cardholder must authenticate (`:customer` only) | See [C](#c-one-click-purchase) |
| `failed` | Refused | Record `pmt_errorcode`; ask for a new card or retry later under your own rules |
| `unknown` | Timed out, waiting, already paid or an undocumented reply | [Settle it](#settling-an-uncertain-charge) before anything else |

`SveaPayments::HTTPError`, `SveaPayments::InvalidResponseError` and network
timeouts also mean unknown: the request may have reached Svea.

```ruby
begin
  result = SveaPayments::CardToken.charge(token, details, secret: secret_key, initiator: :merchant)
  outcome = result['outcome']
rescue SveaPayments::Error, Timeout::Error, SystemCallError, SocketError
  outcome = 'unknown'
end
```

Useful error codes on a `failed` charge: `ERROR_PAYMENT_INSTRUMENT_EXPIRED`
(ask for a new card), `ERROR_PAYMENT_INSTRUMENT_LIMIT_EXCEEDED` and
`ERROR_CARD_AUTHORIZATION_FAILED`.

## Settling an uncertain charge

The gem never retries a charge, and neither should the application until the
earlier attempt is settled. Charging again under a new payment ID while the
first is uncertain can charge the cardholder twice.

```ruby
status = SveaPayments::Payment.query_payment_status(token, charge_id, seller_id)
code = status['pmtq_returncode'].to_i
```

- `20`–`98`: paid. Mark the charge paid.
- `99`: refunded or cancelled.
- `00`–`19`: not confirmed. Svea also answers `00` for a payment it does not
  know. Treat the charge as unpaid only after the uncertainty window has
  clearly passed; until then, keep asking.
- Code `01` raises `SveaPayments::Error`: the query itself failed. It proves
  nothing; ask again later.

Run this from a scheduled job over every charge left in an unknown or pending
state. Svea's documentation also mentions a payment confirmation callback as a
way to learn the result; the gem does not handle that callback. How long to wait before declaring an unconfirmed charge unpaid is not
stated in Svea's documentation; ask Svea.

## Svea's rules for recurring charges

These are the seller's obligations, not something the gem can enforce:

- The cardholder accepts the recurring payment terms before the card is
  registered.
- After registration the cardholder receives a confirmation email containing:
  the text "recurring charging of card", the amount to be charged, how often
  the card will be charged, how long the agreement is valid, and whether the
  amount is fixed or may vary.
- Before every charge the cardholder is told the amount and the date.
- The cardholder can cancel an upcoming or already made recurring charge.
- In principle at most one charge per month, and no recurring charge above the
  original payment.
- A card saved during a purchase must go through 3-D Secure if it will be used
  for recurring charges. Registration through these forms includes it.

Svea also asks sellers to read its and the card companies' terms for recurring
payments before going live.

## Not yet verified

- **Hash calculation.** No test vector could be reproduced, because the
  documentation's example hashes do not publish their secret key. The first
  sandbox registration shows whether Svea accepts the hash.
- **Charge reply hash.** Not checked, because the documentation does not list
  the fields it covers.
- **Test host.** The documentation lists `http://test1.maksuturva.fi`; the gem
  uses `https://test1.maksuturva.fi`.
- **Server-to-server registration.** Documented only as a browser form.
- **Token information and deletion.** Not implemented; the first has an
  ambiguous address in the documentation and the second is not documented.
- **Card on file and the "original payment" limit**, and how long an
  unconfirmed charge can still complete: both are questions for Svea.
