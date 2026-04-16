# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'minitest/test_task'
require 'rubocop/rake_task'

# Default name for this is `:test`
Minitest::TestTask.create

# https://github.com/simplecov-ruby/simplecov/issues/1032#issuecomment-2087973750
Minitest::TestTask.create(:coverage) do |t|
  # simplecov can be configured inside the `test/test_helper.rb` file, but it
  # needs to be required before minitest, otherwise it's at_exit hook won't be
  # registered in the correct order, which will cause coverage to be missed.
  t.test_prelude = 'require "simplecov"'
end

RuboCop::RakeTask.new

task default: %i[coverage rubocop]
