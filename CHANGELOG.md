## Unreleased

- Add saved-card support (requires a separate agreement with Svea):
  `CardToken.registration_form`, `CardToken.payment_with_registration_form`,
  `CardToken.verify_return` and `CardToken.charge` for customer- and
  merchant-initiated token charges, plus `Signature` for the hash-signed
  messages these use. `query_payment_status` now returns token and card fields.
  Follows Svea's documentation; not yet verified against the sandbox.

## [0.2.0] - 2026-11-15

Not yet published. Error handling is not drop-in compatible with 0.1.2.

### Added

- `Payment.refund_before_settlement`: full and partial refunds before
  settlement (`PaymentCancel.pmt`, action `CANCEL`), with the documented return
  codes including 30 "already settled". No automatic fallback or retry.
- `Payment.refund_after_settlement`: refund requests with funding instructions,
  structured errors, duplicate-ID support and strict response handling.
- `SveaPayments::HTTPError`, `InvalidResponseError` and `ReportError`.

### Changed

- Every operation raises `HTTPError` on non-2xx responses and
  `InvalidResponseError` on malformed, incomplete or ambiguous replies, instead
  of returning empty data. Timeouts are bounded and nothing is retried.
- Payment status query: confirmed codes 20–98 must echo the payment and seller
  IDs; code 01 (query failed) raises instead of looking like "unpaid".
- Settlement reports: a result code other than 00 raises `ReportError`; the
  documented "No events found." reply returns an empty report. The reply must
  be a `getCompensationsResponse`, and settlements and orders are read only
  from the documented path, each with its own amounts.
- CSV reports return the exact response bytes; only `XML` and `CSV` formats
  are accepted.
- Minimum Ruby is 3.2. Nokogiri and base64 are declared runtime dependencies.

### Removed

- The unused HTTParty runtime dependency.

## [0.1.2] - 2024-12-08

### Added

- Feature: Added support for report queries

## [0.1.1] - 2024-12-06

### Added

- Feature: Added support for listing payment methods

### Added

- Feature: Added errors to create payment

## [0.1.0] - 2024-08-15

### Added

- Feature: Authentication
- Feature: Create payment
- Feature: Get payment status
