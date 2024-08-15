# SveaPayments

SveaPayments is a Ruby gem for integrating with the Svea Payments API. This gem provides methods for creating payments and querying payment statuses.

## Installation

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

First, obtain an authentication token:

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

    payment_response, status = SveaPayments::Payment.create_payment(token, payment_details)

### Querying Payment Status

To query the status of a payment, use the payment ID:

    payment_status = SveaPayments::Payment.query_payment_status(token, payment_response['pmt_id'], pmt_sellerid)

## Development

After checking out the repo, run bin/setup to install dependencies. Then, run rake spec to run the tests. You can also run bin/console for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run bundle exec rake install. To release a new version, update the version number in version.rb, and then run bundle exec rake release, which will create a git tag for the version, push git commits and the created tag, and push the .gem file to rubygems.org.

## TODO

- Add refunds
- Add reporting

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/akonan/svea_payments.

## License

The gem is available as open source under the terms of the MIT License. 
