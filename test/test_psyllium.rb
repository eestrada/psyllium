# frozen_string_literal: true

require 'async'
require_relative 'test_helper'

class TestPsyllium < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Psyllium::VERSION
  end

  def test_that_it_has_a_fiber_module
    refute_nil ::Psyllium::Fiber
  end

  def test_psyllium_fiber_inherits_psyllium_fiber_methods
    afiber = ::Psyllium::Fiber.new do
      puts 'Hello world'
    end

    assert_kind_of(::Psyllium::FiberMethods, afiber)
  end

  def test_builtin_fiber_does_not_inherit_psyllium_fiber_methods
    afiber = ::Fiber.new do
      puts 'Hello world'
    end

    assert_kind_of(::Psyllium::FiberMethods, afiber)
  end

  def test_kill_method_is_aliased
    fiber_methods = ::Psyllium::Fiber.instance_methods

    skip('kill method not present') unless fiber_methods.include?(:kill)

    assert_includes(fiber_methods, :terminate)
    assert_includes(fiber_methods, :exit)

    kill_method = ::Psyllium::Fiber.instance_method(:kill)
    terminate_method = ::Psyllium::Fiber.instance_method(:terminate)
    exit_method = ::Psyllium::Fiber.instance_method(:exit)

    # Check if these are aliases by checking equality of the unbound methods.
    assert_equal(kill_method, terminate_method)
    assert_equal(kill_method, exit_method)
  end

  def test_join_works
    Async do
      afiber = ::Fiber.new do
        sleep(1)
        # puts 'hello'
        # puts 'world'
        3
      end

      afiber.resume
      end_value = afiber.value

      assert_equal(3, end_value)

      assert_kind_of(::Psyllium::FiberMethods, afiber)
    end
  end
end
