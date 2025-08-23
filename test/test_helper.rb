# frozen_string_literal: true

require 'simplecov'
require 'simplecov-html'
require 'simplecov-cobertura'

SimpleCov.start do
  SimpleCov.formatters = [
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::CoberturaFormatter,
  ]

  enable_coverage :branch
  add_filter '/test/'
end

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'psyllium'

require 'minitest/autorun'
