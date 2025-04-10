# frozen_string_literal: true

require 'async'
require 'fiber_scheduler'
require_relative 'test_helper'

class TestPsyllium < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Psyllium::VERSION
  end

  def test_builtin_fiber_inherits_psyllium_fiber_methods
    afiber = ::Fiber.new do
      puts 'Hello world'
    end

    assert_kind_of(::Psyllium::FiberInstanceMethods, afiber)
  end

  def test_builtin_fiber_inherits_psyllium_fiber_class_methods
    assert_kind_of(::Psyllium::FiberClassMethods, ::Fiber)
  end

  def test_fiber_join_only_works_on_psyllium_fibers
    afiber = Fiber.new do
      Fiber.yield
    end

    afiber.resume

    exc = assert_raises(Psyllium::Error) { afiber.join }
    assert_match('No Psyllium state for this fiber', exc.message)
  end

  def test_fiber_cannot_join_self
    Async do
      Fiber.start do
        exc = assert_raises(Psyllium::Error) do
          Fiber.current.join
        end
        assert_match('Cannot join self', exc.message)
      end
    end
  end

  def test_kill_method_is_aliased
    fiber_methods = ::Fiber.instance_methods

    assert_includes(fiber_methods, :terminate)
    assert_includes(fiber_methods, :exit)

    kill_method = ::Fiber.instance_method(:kill)
    terminate_method = ::Fiber.instance_method(:terminate)
    exit_method = ::Fiber.instance_method(:exit)

    # Check if these are aliases by checking equality of the unbound methods.
    assert_equal(kill_method, terminate_method)
    assert_equal(kill_method, exit_method)
  end

  def test_join_works
    reactors = [
      Kernel.method('Async'),

      # FIXME: FiberScheduler does not work with this test currently
      # Kernel.method('FiberScheduler'),
    ]

    reactors.each do |reactor|
      outer_limit = 0.1
      reactor.call do
        afiber = ::Fiber.start(outer_limit) do |inner_limit|
          sleep(inner_limit)
          3
        end
        bfiber = ::Fiber.start do
          sleep(outer_limit)
          4
        end

        a_end_value = afiber.value
        b_end_value = bfiber.value

        assert_equal(3, a_end_value)

        assert_equal(4, b_end_value)

        assert_kind_of(::Psyllium::FiberInstanceMethods, afiber)

        # Join should return the fiber instance
        assert_equal(afiber, afiber.join)
      end
    end
  end
end
