# Repository review and refund handoff

## Follow-up: five merged-codebase findings addressed locally

Branch: `harden-payment-response-contracts`, based on merged master `e31d3fd`.
This section supersedes the historical non-refund HTTP/CSV findings below.

- Shared GET/POST transport rejects non-2xx, uses strict XML for XML operations,
  sets 10s connect / 30s read-write timeouts, and disables automatic retries.
- Confirmed query codes (20–98) require matching seller/payment IDs; supplied
  IDs on other codes must also match. Code 01 raises because the query failed.
  Scalar extraction rejects duplicate/nested values instead
  of concatenating them. Create success requires an ID and URL.
- Report amounts are scoped to their own compensation/order. CSV returns exact
  bytes; unsupported formats fail before sending.
- Offline success, rejection, malformed-response, identity and transport tests
  cover non-refund operations. Live specs only allow the HTTPS sandbox host.

Verification on Ruby 3.4.9: 154 examples pass, including randomized seed 7129.
Loading the original master implementations against the focused regression
suite yields 62 failures in 78 examples, confirming the tests detect the old
behavior. Gem build and `git diff --check` pass. No live API calls were made.

Compatibility gate: new XML fixtures are synthetic, not provider recordings.
Full live wrapper/error variants remain unverified. Obtain documentation exports
or redacted fixtures and update consumer exception handling before deployment.
No consumer code changes, credential-history cleanup, Ruby-version matrix rerun,
or release are included. Public release remains on hold.

## PR #9 follow-up: release remains on hold

CI now targets Ruby 3.2 and 3.4.9; the gem minimum is 3.2 to match the locked
Nokogiri dependency. Refund responses require matching action/version and
seller/payment identity, unambiguous response fields and a two-digit code.
Code 00 additionally requires nonblank funding instructions and a positive
comma-decimal transfer amount. Other business codes retain their errors without
requiring funding instructions. A different valid transfer amount is allowed.
Malformed replies raise InvalidResponseError with an unknown-outcome warning;
callers must reconcile rather than blindly retry.

Local verification: Ruby 3.4.9, 78 offline examples, zero failures; diff whitespace
checks and CI-matrix/gemspec consistency checks pass. Hosted CI must also pass
before merge. No live refund calls, release or visibility changes were made.
GitHub currently reports the repository itself as public; the hold applies to
publishing a release, not a claim that the repository is private.
Non-refund transport, CSV and consumer-integration findings remain out of scope.

Reviewed baseline: `af528e2`. Working branch: `refund-support-review`.

## Refund status: implemented from the supplied PDF

The user supplied `DOCS-Refund Payment After Settlement-210926-133729.pdf`.
`Payment.refund_after_settlement` now posts to `/PaymentCancel.pmt`, preserving
codes 00/20/90/91/99, transfer instructions and field/general error details.
Code 00 means receipt, not completion: the merchant must separately fund the
refund using the returned amount/reference and Svea bank details. No deadline
is specified in this document. Before-settlement operations remain out of scope.
Refund transport rejects non-2xx and malformed responses and does not retry.
Existing create/query/report transport behavior is unchanged.

### Initial investigation (historical)

No refund operation exists. `README.md` explicitly lists refunds as a TODO.
The payment-status parser exposes `pmtq_amountrefunded`, and reports expose
`refundedAmount`; neither initiates refunds.

The supplied documentation's request/response tables could not be retrieved.
Do not invent the endpoint, action/version, amount representation, response
codes, time limits, or retry behavior. Next input needed: an export or pasted
request and response tables for the refund operation(s) the application needs.

Implementation acceptance criteria once the contract is available:

1. Send the documented authenticated request to the selected environment.
2. Preserve documented response fields and business failure codes.
3. Distinguish acceptance from completion; do not infer a deadline locally.
4. Test success, rejection/expiry, malformed responses and uncertain transport
   outcomes without issuing live refunds or automatically retrying them.
5. Document supported refund stage(s), required inputs and return shape.

## Findings, ranked

### High — HTTP errors and malformed responses are treated as payment results

`lib/svea_payments/base.rb:13-17,24-28` ignores HTTP status and uses permissive
XML parsing. `payment.rb:19-29` then returns empty strings and no errors when
an HTTP 500 body is ordinary HTML. Callers cannot reliably distinguish an API
failure from a parsed result. This is particularly dangerous for future refund
requests with uncertain outcomes. No explicit timeout policy is provided either.

Reproduced offline in `spec/unit/payment_response_spec.rb`. Still unfixed.
Recommendation: typed HTTP/parse errors, bounded configurable timeouts, preserve
business response codes, and no automatic financial-operation retries.

### High — published runtime dependencies are incomplete (fixed locally)

`base.rb` requires Nokogiri but it was only declared in the development Gemfile.
A consumer installing the gem has no guarantee of receiving it. Authentication
also requires base64, which is no longer a default gem on Ruby 3.4; the baseline
test suite failed to load on Ruby 3.4.9 with `cannot load such file -- base64`.

Added both runtime dependencies to the gemspec. Bundler also resolved Nokogiri
from 1.16.2 to 1.19.4 for the installed Ruby/Linux environment. Older supported
Ruby versions and macOS were not exercised; CI currently covers only Ruby 3.0.0.

### Medium — CSV report results are corrupted by XML parsing

`lib/svea_payments/reports.rb:28,41-43` promises raw CSV, but receives and returns
a Nokogiri document from Base. Raw bytes have already been parsed as XML.
Reproduced offline in `spec/unit/payment_response_spec.rb`. Still unfixed.
Recommendation: separate transport from parsing and return the exact CSV body.

### Medium — default tests contact the sandbox and under-check success

The payment, payment-method and report specs call `WebMock.allow_net_connect!`.
The payment spec creates a payment, then only checks that the result contains
the `pmt_id` key, which the implementation always includes even for errors.
Hard-coded credential-like values exist in these tests; their public-demo status
was not verified. Confirm provenance before distributing them; do not assume
they are production credentials or publish them in review artifacts.

Live specs now require `SVEA_LIVE_TESTS=1`. No live tests were executed. The
success assertions and credential sourcing still need improvement. Offline
characterization tests demonstrate bugs; they do not endorse current behavior.

### Medium — README payment example misstates the return shape (fixed locally)

`create_payment` returns a hash, not a `[response, status]` pair. Removed the
misleading second assignment. Other sample payment fields were not validated
against the unavailable API schema and should not be treated as a complete
production request.

## Coverage and verification

After adding refunds: Ruby 3.4.9 `bundle exec rake` passes **30 examples**,
including 26 refund cases. Requests are WebMock-intercepted: success/funding
details, every documented business code, an unknown code, optional parameters,
full/partial amounts, both environments, validation, HTTP errors, malformed
responses and timeout/no-retry behavior. `git diff --check` passes. No live
provider behavior or bank transfer was tested. Original non-refund HTTP/CSV
findings remain intentionally unfixed and covered by characterization tests.

Read all library modules, test setup and specs, README, changelog, gem metadata,
lockfile, CI workflow, executable helpers and RBS placeholder. The Config module
duplicates environment selection and is not required by the gem entry point;
the RBS file declares only VERSION. Neither supplies refund support.

- Initial pre-refund baseline after dependency fixes: Ruby 3.4.9
  `bundle exec rake` — 4 examples, 0 failures; network blocked.
- `SVEA_LIVE_TESTS=1 bundle exec rspec spec/integration --dry-run` — discovers
  11 examples; executes no hooks or test bodies and proves no API behavior.
- Added two explicit characterization tests for HTTP error and CSV defects.
- No live payment/refund calls, release, commit or push.

This is a source review with focused reproductions, not a full security audit
or proof of compatibility with Svea's live API. The initial contract blocker
above was resolved by the supplied PDF; all refund testing remains offline.
