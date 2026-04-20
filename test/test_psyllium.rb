# frozen_string_literal: true

require_relative 'minitest_helper'

require 'async'
require_relative '../lib/psyllium'

class TestPsyllium < Minitest::Test # rubocop:disable Metrics/ClassLength
  class TestException < StandardError
  end

  def setup
    super
    @scheduler = Async::Scheduler.new
    Fiber.set_scheduler(@scheduler)
  end

  def teardown
    super
    Fiber.set_scheduler(nil)
    @scheduler = nil
  end

  def test_modules_prepended
    assert_equal(::Psyllium::FiberClassMethods, ::Fiber.singleton_class.ancestors.first)
    assert_equal(::Psyllium::FiberInstanceMethods, ::Fiber.new {}.class.ancestors.first) # rubocop:disable Lint/EmptyBlock
  end

  def test_that_it_has_a_version_number
    refute_nil ::Psyllium::VERSION
  end

  def test_builtin_fiber_inherits_psyllium_fiber_methods
    fiber1 = ::Fiber.new do
      puts 'Hello world'
    end

    assert_kind_of(::Psyllium::FiberInstanceMethods, fiber1)
  end

  def test_builtin_fiber_inherits_psyllium_fiber_class_methods
    assert_kind_of(::Psyllium::FiberClassMethods, ::Fiber)
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

  def test_overridden_new_without_block
    Fiber.schedule do
      err = assert_raises(ArgumentError) { Fiber.new }
      assert_equal('No block given', err.message)
    end
  end

  def test_start_without_block
    Fiber.schedule do
      err = assert_raises(ArgumentError) { Fiber.start }
      assert_equal('No block given', err.message)
    end
  end

  def test_status_exceptional_completion1
    Fiber.schedule do
      fiber1 = ::Fiber.start do
        raise TestException.new('Test exception message')
      end

      refute_nil(fiber1)

      fiber1.join

      err = assert_raises(TestException) { fiber1.value }
      assert_equal('Test exception message', err.message)
    end
  end

  # FIXME: there is like 2-3 different behaviors being tested in this test and
  # it should be split up.
  def test_status_exceptional_completion2 # rubocop:disable Metrics/AbcSize
    Fiber.schedule do
      fiber1 = ::Fiber.new do
        ::Fiber.yield
        raise TestException.new('Test exception message2')
      end

      assert_equal('sleep', fiber1.status)
      fiber1.resume

      assert_equal('sleep', fiber1.status)

      err0 = assert_raises(Psyllium::Error) { fiber1.join }
      assert_equal('Cannot join unless started via Fiber.schedule', err0.message)

      err1 = assert_raises(TestException) { fiber1.resume }
      assert_equal('Test exception message2', err1.message)

      err2 = assert_raises(FiberError) { fiber1.resume }
      assert_equal('attempt to resume a terminated fiber', err2.message)

      # After a Fiber has completed, there is no reason to disallow it from
      # joining, even if it wasn't started via Fiber.schedule.
      #
      # This allows even blocking or non-scheduled fibers to still benefit from
      # the state tracking of Psyllium.
      err3 = assert_raises(TestException) { fiber1.value }
      assert_equal('Test exception message2', err3.message)
    end
  end

  def test_status_run
    Fiber.schedule do
      assert_equal('run', Fiber.current.status)
    end
  end

  def test_status_sleep
    Fiber.schedule do
      fiber1 = ::Fiber.start { sleep(0.01) }

      assert_equal('sleep', fiber1.status)
    end
  end

  def test_status_complete_exceptional1
    Fiber.schedule do
      fiber1 = ::Fiber.start do
        raise 'Any exception'
      end

      refute_nil(fiber1)

      fiber1.join

      assert_nil(fiber1.status)
    end
  end

  def test_status_complete_exceptional2
    fiber1 = Fiber.new do
      assert_equal('run', Fiber.current.status)
      Fiber.yield
    end

    assert_equal('sleep', fiber1.status)

    fiber1.resume

    assert_equal('sleep', fiber1.status)

    fiber1.resume

    assert_equal(false, fiber1.status) # rubocop:disable Minitest/RefuteFalse
  end

  def test_status_complete_normal
    Fiber.schedule do
      fiber1 = ::Fiber.start { sleep(0.01) }

      refute_nil(fiber1)

      fiber1.join

      assert_equal(false, fiber1.status) # rubocop:disable Minitest/RefuteFalse
    end
  end

  def test_stop_with_sleep
    Fiber.schedule do
      fiber1 = ::Fiber.start { sleep(0.01) }

      assert_equal('sleep', fiber1.status)
      assert_predicate(fiber1, :alive?)

      assert_predicate(fiber1, :stop?)
    end
  end

  def test_stop_with_completed
    Fiber.schedule do
      fiber1 = ::Fiber.start { sleep(0.01) }
      fiber1.join

      assert_equal(false, fiber1.status) # rubocop:disable Minitest/RefuteFalse
      refute_predicate(fiber1, :alive?)

      assert_predicate(fiber1, :stop?)
    end
  end

  def test_join_works
    # Need to run this under a non-blocking Fiber, otherwise joining won't work.
    Fiber.schedule do
      outer_limit = 0.1
      fiber1 = ::Fiber.start(outer_limit) do |inner_limit|
        sleep(inner_limit)
        3
      end
      fiber2 = ::Fiber.start do
        sleep(outer_limit)
        4
      end

      end_value1 = fiber1.value
      end_value2 = fiber2.value

      assert_equal(3, end_value1)

      assert_equal(4, end_value2)

      assert_kind_of(::Psyllium::FiberInstanceMethods, fiber1)

      # Join should return the fiber instance
      assert_equal(fiber1, fiber1.join)
    end
  end

  def test_join_timeout_works
    # Need to run this under a non-blocking Fiber, otherwise joining won't work.
    Fiber.schedule do
      fiber1 = ::Fiber.start do
        sleep(0.1)
      end

      timeout_value1 = fiber1.join(0.05)

      assert_nil(timeout_value1)

      timeout_value2 = fiber1.join(0.15)

      refute_nil(timeout_value2)
    end
  end

  def test_fiber_cannot_join_self
    Fiber.start do
      exc = assert_raises(Psyllium::Error) do
        Fiber.current.join
      end
      assert_match('Cannot join self', exc.message)
    end
  end

  def test_join_fails_on_blocking_parent_fiber
    Fiber.blocking do
      fiber1 = Fiber.new { sleep(0) }

      err = assert_raises(Psyllium::Error) { fiber1.join }
      assert_equal('Cannot join when current Fiber is blocking', err.message)
    end
  end

  def test_join_fails_on_blocking_self_fiber
    Fiber.schedule do
      fiber1 = ::Fiber.new(blocking: true) { sleep(0.1) }

      err = assert_raises(Psyllium::Error) { fiber1.join }
      assert_equal('Cannot join when called Fiber is blocking', err.message)
    end
  end

  def test_join_fails_on_scheduler_not_set
    Fiber.set_scheduler(nil)

    fiber1 = Fiber.new { sleep(0) }

    err = assert_raises(Psyllium::Error) { fiber1.join }
    assert_equal('Cannot join without Fiber scheduler set', err.message)
  end

  def test_fiber_join_only_works_on_started_fibers
    Fiber.schedule do
      fiber1 = ::Fiber.new { sleep(0.01) }

      exc = assert_raises(Psyllium::Error) { fiber1.join }
      assert_match('Cannot join when Fiber has not started', exc.message)
    end
  end
end
