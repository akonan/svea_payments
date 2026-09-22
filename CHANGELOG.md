
## Unreleased

- Keep public gem release on hold pending the remaining review findings.
- Align the minimum Ruby requirement and CI with Nokogiri (Ruby >= 3.2),
  testing Ruby 3.2 and 3.4.9.
- Reject incomplete, mismatched and ambiguous refund responses, and require
  funding instructions for accepted requests. Preserve business rejections
  without requiring funding details; never retry an uncertain refund outcome.

- Add after-settlement refund requests with funding instructions, structured
  errors, duplicate-ID support, strict response handling and offline tests.
- Declare Nokogiri and base64 runtime dependencies; make live tests opt-in.

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
