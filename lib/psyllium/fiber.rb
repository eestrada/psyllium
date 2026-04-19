# frozen_string_literal: true

require 'timeout'

module Psyllium
  # Base Exception class for module code.
  class Error < FiberError; end

  # Holds per-Fiber state for Psyllium operations.
  class State
    attr_reader :mutex
    attr_accessor :nested, :started, :joined, :value, :exception

    def initialize
      @mutex = Thread::Mutex.new
      @nested = false
      @started = false
      @joined = false
      @value = nil
      @exception = nil
    end
  end

  # Meant to be used with `extend` on Fiber class.
  module FiberClassMethods
    def new(*args, **kwargs, &block)
      ::Kernel.raise ArgumentError.new('No block given') unless block

      super(*args, **kwargs) do # rubocop:disable Style/SuperArguments
        state = state_get
        state.mutex.synchronize do
          state.started = true
          value = block.call
          state.value = value unless state.nested
          value
        rescue Exception => e # rubocop:disable Lint/RescueException
          state.exception = e
          raise
        ensure
          state.joined = true
        end
      end
    end

    # A new method is used to create Psyllium Fibers for several reasons:
    #
    # 1. This ensures that existing behavior for Fibers is not changed.
    #
    # 2. Modifying the actual instances variables of Fibers does not work well
    # with certain schedulers like Async which expect to also wrap the given
    # block in another block.
    #
    # 3. The `start` method is also available on the `Thread` class, so this
    # makes it easy to change out one for the other.
    def start(*args, &start_block)
      # Because of how some Schedulers (read Async) wrap things, we will be
      # double wrapped, like this:
      # <Psyllium `new` proc> -> <scheduler proc> -> <Psyllium `start` proc> -> <caller supplied proc>
      ::Kernel.raise ArgumentError.new('No block given') unless start_block

      ::Fiber.schedule do
        state = state_get

        # Use `nested` state to ensure the enclosing Psyllium `new` proc does
        # *not* overwrite the returned `value` or `exception`, since those
        # would be ones returned by the fiber scheduler proc, which may or may
        # not return the value we want.
        state.nested = true

        # If this internal proc raises an exception before hitting a blocking
        # operation, then the `schedule` method for the Async fiber scheduler
        # will return `nil` instead of a completed or blocked Fiber. This is
        # probably a bug in behavior for the Async scheduler. Regardless, we
        # need to work around it for now. Calling `sleep` for zero seconds
        # ensures that we *always* return a working fiber that is scheduled on
        # the FiberScheduler. It should get run immediately, the next time the
        # scheduler runs.
        sleep(0)

        state.value = start_block.call(*args)
      rescue Exception => e # rubocop:disable Lint/RescueException
        state.exception = e
        # Forcefully suppress all exceptions to behave more like Thread.start
      end
    end

    def state_get(fiber: Fiber.current)
      # Psyllium state is a thread local variable because Fibers cannot (yet)
      # migrate across threads anyway.
      #
      # A `WeakKeyMap` is used so that when a Fiber is garbage collected, the
      # associated Psyllium::State will be garbage collected as well.
      state = Thread.current.thread_variable_get(:psyllium_state) || Thread.current.thread_variable_set(
        :psyllium_state, ObjectSpace::WeakKeyMap.new
      )
      state[fiber] ||= State.new
    end
  end

  # A module meant to extend the builtin Fiber class to make it easier to use
  # in a more Thread-like manner.
  module FiberInstanceMethods
    # Waits for Fiber to complete, using join, and returns its value. If Fiber
    # completed with an exception, re-raises the original exception.
    def value
      join
      ::Kernel.raise state.exception if state.exception

      state.value
    end

    # Mimic Thread `status` method.
    #
    # `"run"` will only be returned if this method is called on
    # `Fiber.current`.
    #
    # `"sleep"` is returned for any Fiber that is `alive?`, but not
    # `Fiber.current`.
    #
    # `nil` is returned if the Fiber completed with an exception.
    #
    # `false` is returned if the Fiber completed without exception.
    #
    # `"abort"` status is never returned because a Fiber does not have a state
    # like this that is detectable or observable. If `kill` is called on a
    # Fiber, the operation will happen immediately; there is not a point in
    # time where `status` can be called between the call to `kill` and the
    # point at which the Fiber is killed.
    def status
      if self == ::Fiber.current
        'run'
      elsif alive?
        'sleep'
      elsif state.exception
        nil
      else
        false
      end
    end

    # Mimic Thread `stop?` method.
    #
    # Return `true` if sleeping or completed.
    def stop?
      status == 'sleep' || !alive?
    end

    # Wait until execution completes. Return the Fiber instance. If `limit` is
    # reached, returns `nil` instead.
    #
    # `join` may be called more than once.
    def join(limit = nil) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      return self if state.joined

      ::Kernel.raise Error.new('Cannot join self') if eql?(::Fiber.current)
      ::Kernel.raise Error.new('Cannot join without Fiber scheduler set') unless ::Fiber.scheduler
      ::Kernel.raise Error.new('Cannot join when current Fiber is blocking') if ::Fiber.current.blocking?
      ::Kernel.raise Error.new('Cannot join when called Fiber is blocking') if blocking?
      ::Kernel.raise Error.new('Cannot join when Fiber has not started') unless state.started
      ::Kernel.raise Error.new('Cannot join unless started via Fiber.schedule') unless state.nested

      # Once this mutex finishes synchronizing, that means the initial
      # calculation is done and we can return `self`, which is the Fiber
      # instance.
      Timeout.timeout(limit) { state.mutex.synchronize { self } }
    rescue Timeout::Error
      # mimic Thread behavior by returning `nil` on timeout.
      nil
    end

    private

    def state
      self.class.state_get(fiber: self)
    end
  end
end

class ::Fiber # rubocop:disable Style/Documentation,Style/OneClassPerFile
  class << self
    prepend ::Psyllium::FiberClassMethods
  end

  prepend ::Psyllium::FiberInstanceMethods

  # Thread has the same aliases
  alias terminate kill
  alias exit kill
end
