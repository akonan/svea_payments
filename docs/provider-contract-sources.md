# Provider contract sources

Svea's public API documentation, read on 2026-11-15 through the Confluence REST
API (`/wiki/rest/api/content/<page id>?expand=body.view`), which serves the
field tables that the rendered pages did not expose to earlier retrieval.
Index: https://sveapayments.atlassian.net/wiki/spaces/DOCS/pages/1657012281/API

| Operation | Page (id, version) | Used for |
| --- | --- | --- |
| Authentication | 1733197825, v3 | HTTP Basic with seller id and secret key on all server-to-server calls |
| Payment status query | 1657012590, v9; examples 1657014098, v7 | `pmtq` root, fields, identity echoed on every example |
| Status codes | 1657012617 | 00–19 not confirmed, 20–98 confirmed, 99 refunded/cancelled, 01 query failed |
| Refund or cancel before settlement | 1657012799, v21; examples 1657014119, v4 | `refund_before_settlement` request, response and codes 00/20/30/31/90/91/99 |
| Refund after settlement | 1657012824 | `refund_after_settlement` |
| Settlement report | 1657012958, v26; 1657012937, v13; examples 1657014136 | `getCompensationsResponse` structure, error replies |
| Card tokenization and charging | 1657013059, v13 | `CardToken`: endpoints, versions 4504/4304/4104/4204, FI50, reply examples, error codes, token fields in status query |
| Hash generation (legacy space DOCSLEGACY) | 262253, v18 | `Signature`: string format, request field order, charset rules |
| Payment response (DOCSLEGACY) | 4751379, v15 | hash fields of the buyer's return |
| Report schema | https://www.maksuturva.fi/smtschema/GetCompensationsResponse.xsd | result codes 00/91/95/99, element paths |

Notes:

- A status query for a payment Svea does not know answers 00 with amount 0,00,
  not 01.
- The status query page lists `pmtq_version` 0006; Svea's own examples send
  0005, which is what this gem sends.
- Report error replies use a namespace-prefixed root
  (`ns2:getCompensationsResponse`) with unprefixed children.
- "No events found." and request errors share result code 95; only the exact
  documented text is treated as an empty report.
- Not implemented: delivery information, invoice tokenization, invoice and
  part-payment server-to-server APIs, JSON/XLS report formats, the token
  information endpoint and hash checks on status query and charge replies.
- Card tokenization open points: no reproducible hash test vector (the example
  hashes use an unpublished secret; the published sandbox secret does not
  reproduce them); the charge reply's hash fields are undocumented; the docs
  show `http://test1` for the token endpoints while the gem uses https; the
  token information URL format is ambiguous.

Nothing here was verified against Svea's sandbox or production.
