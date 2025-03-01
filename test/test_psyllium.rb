# frozen_string_literal: true

require_relative 'test_helper'

class TestPsyllium < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Psyllium::VERSION
  end

  def test_that_it_has_a_fiber_module
    refute_nil ::Psyllium::Fiber
  end

  def test_fiber_inherits_psyllium_fiber
    afiber = ::Fiber.new do
      puts 'Hello world'
    end
    assert_kind_of(::Psyllium::Fiber, afiber)
  end
end
