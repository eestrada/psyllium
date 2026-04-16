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

require 'minitest/autorun'
