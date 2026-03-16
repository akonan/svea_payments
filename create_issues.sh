#!/usr/bin/env bash
#
# Creates GitHub issues for svea_payments code review findings.
# Requires: gh CLI (https://cli.github.com/) authenticated with `gh auth login`
#
# Usage: ./create_issues.sh
#
set -euo pipefail

REPO="akonan/svea_payments"

create_issue() {
  local title="$1"
  local labels="$2"
  local body="$3"
  echo "Creating: $title"
  gh issue create --repo "$REPO" --title "$title" --label "$labels" --body "$body"
  echo "---"
}

# Ensure labels exist (gh will error if they don't)
gh label create "bug" --repo "$REPO" --color "d73a4a" --description "Something isn't working" --force 2>/dev/null || true
gh label create "enhancement" --repo "$REPO" --color "a2eeef" --description "New feature or request" --force 2>/dev/null || true
gh label create "documentation" --repo "$REPO" --color "0075ca" --description "Improvements or additions to documentation" --force 2>/dev/null || true
gh label create "security" --repo "$REPO" --color "e4e669" --description "Security concern" --force 2>/dev/null || true
gh label create "testing" --repo "$REPO" --color "bfd4f2" --description "Related to tests" --force 2>/dev/null || true

# --- Issue 1: Critical ---
create_issue \
  "Replace httparty with nokogiri as runtime dependency" \
  "bug" \
  "$(cat <<'EOF'
## Problem

The gemspec declares `httparty` (~> 0.18) as a runtime dependency, but the gem never uses it. Instead, `base.rb` uses `Net::HTTP` directly and `nokogiri` for XML parsing.

Anyone installing this gem will get a `LoadError` on first use unless they happen to have nokogiri installed as a transitive dependency.

**File:** `svea_payments.gemspec:27`

## Fix

```ruby
# Remove:
spec.add_dependency "httparty", "~> 0.18"

# Add:
spec.add_dependency "nokogiri", "~> 1.16"
```

## Severity
Critical — gem will fail on a fresh install.
EOF
)"

# --- Issue 2: Critical ---
create_issue \
  "Add HTTP error handling and timeouts to Base module" \
  "bug" \
  "$(cat <<'EOF'
## Problem

`lib/svea_payments/base.rb` has no error handling:

- **No timeouts** — HTTP connections can hang indefinitely
- **No status code checks** — a 500 response is parsed as XML, producing confusing Nokogiri errors
- **No rescue blocks** — network errors bubble up as raw Ruby exceptions

## Suggested Fix

```ruby
def send_post_request(uri, form_data, token)
  request = Net::HTTP::Post.new(uri)
  request.content_type = 'application/x-www-form-urlencoded'
  request.body = form_data
  request['Authorization'] = token

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
    http.open_timeout = 30
    http.read_timeout = 30
    http.request(request)
  end

  unless response.is_a?(Net::HTTPSuccess)
    raise SveaPayments::Error, "HTTP #{response.code}: #{response.message}"
  end

  Nokogiri::XML(response.body)
rescue Net::OpenTimeout, Net::ReadTimeout => e
  raise SveaPayments::Error, "Request timed out: #{e.message}"
rescue SocketError, Errno::ECONNREFUSED => e
  raise SveaPayments::Error, "Connection failed: #{e.message}"
end
```

Apply the same pattern to `send_get_request`.

## Severity
Critical — production requests can hang or produce misleading errors.
EOF
)"

# --- Issue 3: Critical ---
create_issue \
  "Fix broken private modifier on class methods in Reports" \
  "bug" \
  "$(cat <<'EOF'
## Problem

In `lib/svea_payments/reports.rb:47`, the `private` keyword is used before `self.parse_compensations` and `self.parse_orders`. However, Ruby's `private` only affects instance methods — it has no effect on `self.` class methods.

Both methods remain publicly accessible despite the intended encapsulation.

## Fix

Option A — inline:
```ruby
private_class_method def self.parse_compensations(xml_doc)
  # ...
end

private_class_method def self.parse_orders(compensation)
  # ...
end
```

Option B — declaration at end of class:
```ruby
private_class_method :parse_compensations, :parse_orders
```

## Severity
Critical — internal parsing methods are unintentionally part of the public API.
EOF
)"

# --- Issue 4: Security ---
create_issue \
  "Move test credentials to environment variables" \
  "security" \
  "$(cat <<'EOF'
## Problem

Test sandbox credentials are hardcoded directly in spec files:

- `spec/integration/payment_spec.rb:14-15`
- `spec/integration/reports_spec.rb:15-16`

```ruby
username = 'ILQXQZEI'
password = 'Pyq8kd5CFSMSuCxate26xHw73edZyg2ytUQMqJPQ'
```

While these are Svea's public test sandbox credentials, hardcoding credentials in source code sets a bad pattern and could trip secret scanners.

## Fix

Use environment variables with fallback to test defaults:

```ruby
let(:username) { ENV.fetch('SVEA_TEST_USERNAME', 'ILQXQZEI') }
let(:password) { ENV.fetch('SVEA_TEST_PASSWORD', 'Pyq8kd5CFSMSuCxate26xHw73edZyg2ytUQMqJPQ') }
```

Or use a `.env` file (added to `.gitignore`) with a `.env.example` template.
EOF
)"

# --- Issue 5: Testing ---
create_issue \
  "Add proper unit tests with WebMock stubs" \
  "testing" \
  "$(cat <<'EOF'
## Problem

The test suite is almost entirely integration tests that hit the live Svea test API:

- Tests toggle `WebMock.allow_net_connect!` to bypass the HTTP mock
- Tests are non-deterministic, slow, and fail without network access
- The only unit test checks the version number
- No unit tests for `Base`, `Authentication`, `Payment`, `PaymentMethods`, or `Reports`

## Suggested Approach

1. Add WebMock stubs with realistic XML response fixtures for each endpoint
2. Test happy path and error scenarios (HTTP 4xx/5xx, timeouts, malformed XML)
3. Keep a small number of integration tests tagged `:integration` that can run against the sandbox
4. Make the default `rake spec` only run unit tests

```ruby
# Example unit test with WebMock
it 'creates a payment and returns response hash' do
  stub_request(:post, "https://test1.maksuturva.fi/NewPaymentExtended.pmt")
    .to_return(status: 200, body: fixture('create_payment_response.xml'))

  response = SveaPayments::Payment.create_payment(token, payment_details)
  expect(response['pmt_id']).to eq('12345')
end
```
EOF
)"

# --- Issue 6: Cleanup ---
create_issue \
  "Remove unused Config module" \
  "enhancement" \
  "$(cat <<'EOF'
## Problem

`lib/svea_payments/config.rb` defines a `SveaPayments::Config` module that duplicates the `base_url` logic already present in the main `SveaPayments` module (`lib/svea_payments.rb:32-34`).

This file is never required by any other file and the module is never used.

## Fix

Delete `lib/svea_payments/config.rb`.
EOF
)"

# --- Issue 7: Consistency ---
create_issue \
  "Use consistent hash key types in return values" \
  "enhancement" \
  "$(cat <<'EOF'
## Problem

Return values use inconsistent key types:

- `Payment.create_payment` returns `{'pmt_id' => ...}` (string keys)
- `Payment.query_payment_status` returns `{'pmtq_action' => ...}` (string keys)
- `PaymentMethods.get_available_payment_methods` returns `[{code: ..., displayname: ...}]` (symbol keys)

This forces consumers to remember which methods use which key type.

## Fix

Pick one convention (string keys to match the API field names is probably simplest) and apply it consistently across all return values.
EOF
)"

# --- Issue 8: Documentation ---
create_issue \
  "Fix incorrect API example in README" \
  "documentation" \
  "$(cat <<'EOF'
## Problem

`README.md:48` shows:

```ruby
payment_response, status = SveaPayments::Payment.create_payment(token, payment_details)
```

But `create_payment` returns a single hash, not a tuple. The destructuring will assign the hash to `payment_response` and `nil` to `status`.

## Fix

```ruby
response = SveaPayments::Payment.create_payment(token, payment_details)
```
EOF
)"

# --- Issue 9: Cleanup ---
create_issue \
  "Remove unnecessary safe navigation in query_payment_status" \
  "enhancement" \
  "$(cat <<'EOF'
## Problem

In `lib/svea_payments/payment.rb:53-73`, `query_payment_status` uses the pattern:

```ruby
xml_doc.xpath("//pmtq_action")&.text.to_s
```

`xpath()` never returns `nil` — it returns an empty `Nokogiri::XML::NodeSet`. The `&.` safe navigation operator is unnecessary throughout this method. The `.to_s` call is also redundant since `.text` already returns a string.

Meanwhile, `create_payment` uses the simpler `.xpath("//pmt_id").text` pattern for the same kind of operation.

## Fix

Use the same pattern as `create_payment`:

```ruby
'pmtq_action' => xml_doc.xpath("//pmtq_action").text,
```
EOF
)"

# --- Issue 10: Bug ---
create_issue \
  "Fix broken require glob in spec_helper.rb" \
  "bug" \
  "$(cat <<'EOF'
## Problem

`spec/spec_helper.rb:9` contains:

```ruby
Dir[File.join(__dir__, 'spec/**/*.rb')].each { |f| require f }
```

Since `__dir__` resolves to the `spec/` directory, this glob looks for files matching `spec/spec/**/*.rb`, which doesn't exist. The line does nothing.

## Fix

Either remove the line (specs are already loaded by RSpec via the `.rspec` config), or fix the glob:

```ruby
Dir[File.join(__dir__, '**/*_spec.rb')].each { |f| require f }
```
EOF
)"

# --- Issue 11: CI ---
create_issue \
  "Update CI to test multiple Ruby versions" \
  "enhancement" \
  "$(cat <<'EOF'
## Problem

`.github/workflows/main.yml` only tests Ruby 3.0.0, but the gemspec declares `required_ruby_version = ">= 2.6.0"`.

This means compatibility with Ruby 2.6, 2.7, 3.1, 3.2, and 3.3 is untested.

## Fix

Use a matrix strategy:

```yaml
strategy:
  matrix:
    ruby-version: ['2.7', '3.0', '3.1', '3.2', '3.3']
```

Or raise the minimum Ruby version to something more current (e.g., `>= 3.0`), since Ruby 2.6 and 2.7 are EOL.
EOF
)"

# --- Issue 12: Metadata ---
create_issue \
  "Add source_code_uri and changelog_uri to gemspec metadata" \
  "enhancement" \
  "$(cat <<'EOF'
## Problem

The gemspec only sets `homepage_uri` in metadata. RubyGems.org prominently displays `source_code_uri` and `changelog_uri` links, which help users find the repository and track changes.

## Fix

```ruby
spec.metadata["homepage_uri"] = spec.homepage
spec.metadata["source_code_uri"] = "https://github.com/akonan/svea_payments"
spec.metadata["changelog_uri"] = "https://github.com/akonan/svea_payments/blob/master/CHANGELOG.md"
```
EOF
)"

# --- Issue 13: Feature ---
create_issue \
  "Implement refunds API" \
  "enhancement" \
  "$(cat <<'EOF'
## Description

The README lists refunds as a TODO item. For a payment gem used in production, refund support is an important feature.

The Svea Payments API supports refunds via the `PaymentCancel.pmt` endpoint.

## Suggested Implementation

Create `lib/svea_payments/refund.rb`:

```ruby
module SveaPayments
  class Refund
    extend Base

    def self.cancel_payment(token, cancel_details)
      uri = URI("#{SveaPayments.base_url}/PaymentCancel.pmt")
      # ...
    end
  end
end
```

Refer to the Svea Payments API documentation for the exact request/response format.
EOF
)"

echo ""
echo "All 13 issues created successfully!"
