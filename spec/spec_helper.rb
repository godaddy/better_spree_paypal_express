# frozen_string_literal: true

if ENV["COVERAGE"]
  require_relative 'rcov_exclude_list.rb'
  exlist = Dir.glob(@exclude_list)
  require 'simplecov'
  require 'simplecov-rcov'
  SimpleCov.formatter = SimpleCov::Formatter::RcovFormatter
  SimpleCov.start do
    exlist.each do |p|
      add_filter p
    end
  end
end

# Configure Rails Environment
ENV['RAILS_ENV'] = 'test'

require File.expand_path('../dummy/config/environment.rb',  __FILE__)

require 'rspec/rails'
require 'ffaker'
require 'byebug'

Dir[File.join(File.dirname(__FILE__), 'support/**/*.rb')].each { |f| require f }

require 'spree/testing_support/factories'
require 'spree/testing_support/controller_requests'
require 'spree/testing_support/authorization_helpers'
require 'spree/testing_support/url_helpers'

RSpec.configure do |config|
  config.include Spree::TestingSupport::UrlHelpers
  config.include Spree::TestingSupport::AuthorizationHelpers::Controller

  config.mock_with :rspec
  config.color = true
  config.use_transactional_fixtures = true
  config.disable_monkey_patching!

  config.fail_fast = ENV['FAIL_FAST'] || false
end

if ENV["COVERAGE"]
  # Load all files except the ones in exclude list
  require_all(Dir.glob('**/*.rb') - exlist)
end
