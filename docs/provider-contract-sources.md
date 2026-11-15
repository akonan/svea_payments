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
- Not implemented: delivery information, card tokenization and token charges,
  invoice/part-payment server-to-server APIs, JSON/XLS report formats, and the
  optional response hashes.

Nothing here was verified against Svea's sandbox or production.
