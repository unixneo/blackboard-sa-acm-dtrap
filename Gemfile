source "https://rubygems.org"

ruby "3.2.2"

gem "rails", "~> 7.1.6"
gem "sprockets-rails"
gem "pg", "~> 1.5"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", require: false

# Environment variables
gem "dotenv-rails"

# LLM integration
gem "ruby-anthropic"

# Background jobs
gem "sidekiq", "~> 8.1"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ]
end

group :development do
  gem "web-console"
  gem "listen"
end
gem "redis", "~> 5.0"
