require_relative "lib/svea_payments/version"

Gem::Specification.new do |spec|
  spec.name = "svea_payments"
  spec.version = SveaPayments::VERSION
  spec.authors = ["Antti Akonniemi"]
  spec.email = ["antti@kiskolabs.com"]

  spec.summary = "Ruby gem to create payments with Svea Payments API."
  spec.homepage = "https://www.github.com/akonan/svea_payments"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  
  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.add_dependency "httparty", "~> 0.18"
  spec.add_development_dependency 'rspec', '~> 3.10'

end
