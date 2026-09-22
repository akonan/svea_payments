# Query-status correction — deployment hold

## Source and scope

User-provided PDF: `Svea Payments API - Svea Payments.pdf`, exported 2026-09-22.
Page title: **Payment and Delivery status code values**, updated 2023-01-13.
Source: https://sveapayments.atlassian.net/wiki/spaces/DOCS/pages/1657012617

The documentation says 00–19 is not confirmed, 20–98 is confirmed, and 99 is
fully refunded/cancelled. Listed confirmed codes: 20, 30, 40, 91, 92, 93, 95, 98.
Code 01 specifically means the query failed. It must not become proof of nonpayment.
Code 00 means not paid, not a generic successful-payment code.

This corrects PR #10's mistaken treatment of non-00 query codes as rejections.
Nauramaan-com's existing 20–98 confirmation range agrees with the provider's
documented rule; the review's criticism of that range is withdrawn.

## Verification plan

1. Add regressions before implementation: every confirmed code requires both
   matching identifiers; unpaid replies may omit them but cannot supply mismatches.
2. A query-failed reply must raise rather than reach a caller's unpaid path.
3. Preserve provider codes/text, including cancellation/refund code 99.
4. Run focused tests against the old implementation, then all offline tests on
   the fix; inspect CI without enabling live tests.

## Remaining gates

This PDF establishes code meanings, not the full XML schema. Query/create/report
XML wrappers still need authoritative exports or redacted provider fixtures.
PR #10 stays draft. No merge, release, deployment, live calls or consumer gem-pin
upgrade is authorized. The app's durable-attempt, UI exception, report and refund
work remains a separate PR; do not describe this correction as fixing those paths.

## Verification evidence

- New focused suite before the fix: 62 examples, 19 failures.
- After correction: 216 offline examples pass on Ruby 3.4.9, including randomized
  seed 27103. No live requests. `git diff --check` passes.
- Preflight ran with automatic project checks disabled in favor of the explicit
  gem RSpec/rake suite above. Provider XML shape remains a separate gate.
