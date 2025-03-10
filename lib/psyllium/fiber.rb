# frozen_string_literal: true

require 'timeout'

module Psyllium
  # Wrap Exception instances for propagation
  class ExceptionalCompletionError < FiberError
    def initialize(expt)
      @internal_exception = expt
      super(@internal_exception)
    end

    def cause
      @internal_exception
    end
  end

  # Holds per-Fiber state for Psyllium operations.
  class State
    attr_reader :mutex
    attr_accessor :started, :joined, :value, :exception

    def initialize
      @mutex = Thread::Mutex.new
      @started = false
      @joined = false
      @value = nil
      @exception = nil
    end
  end

  # Meant to be used with `extend` on Fiber class.
  module FiberClassMethods
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
    def start(&block)
      raise ArgumentError.new('No block given') unless block

      Fiber.schedule do
        state = state_get(create_missing: true)
        state.mutex.synchronize do
          state.started = true
          state.value = block.call
        rescue StandardError => e
          state.exception = e
        ensure
          state.joined = true
        end
      end
    end

    def state_get(fiber: Fiber.current, create_missing: false)
      # Psyllium state is a thread local variable because Fibers cannot (yet)
      # migrates across threads anyway.
      #
      # A `WeakKeyMap` is used so that when a Fiber is garbage collected, the
      # associated Psyllium::State will be garbage collected as well.
      state = Thread.current.thread_variable_get(:psyllium_state) || Thread.current.thread_variable_set(
        :psyllium_state, ObjectSpace::WeakKeyMap.new
      )
      create_missing ? (state[fiber] ||= State.new) : state[fiber]
    end
  end

  # A module meant to extend the builtin Fiber class to make it easier to use
  # in a more Thread-like manner.
  module FiberInstanceMethods
    # Waits for Fiber to complete, using join, and returns its value. If Fiber
    # completed with an exception, raises `ExceptionalCompletionError`, with
    # the original exception as its `cause`.
    def value
      join
      raise ExceptionalCompletionError.new(state.exception) if state.exception

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
      elsif state(suppress_error: true)&.exception
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
    def join(limit = nil) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/AbcSize
      return self if state.joined
      raise FiberError.new('Cannot join self') if eql?(::Fiber.current)
      raise FiberError.new('Cannot join when calling Fiber is blocking') if ::Fiber.current.blocking?
      raise FiberError.new('Cannot join when called Fiber is blocking') if blocking?
      raise FiberError.new('Cannot join without Fiber scheduler set') unless ::Fiber.scheduler
      raise FiberError.new('Cannot join unstarted Fiber') unless state.started

      # Once this mutex finishes synchronizing, that means the initial
      # calculation is done and we can return `self`, which is the Fiber
      # instance.
      Timeout.timeout(limit) { state.mutex.synchronize { self } }
    rescue Timeout::Error
      # mimic Thread behavior by returning `nil` on timeout.
      nil
    end

    private

    def state(suppress_error: false)
      fiber_state = self.class.state_get(fiber: self)
      raise Error.new('No Psyllium state for this fiber') unless fiber_state || suppress_error

      fiber_state
    end
  end

  # Inherits from the builtin Fiber class, and adds additional functionality to
  # make it behave more like a Thread.
  class Fiber < ::Fiber
    extend ::Psyllium::FiberClassMethods
    # This must be prepended so that its implementation of `initialize` is called
    # first.
    include ::Psyllium::FiberInstanceMethods

    # The `Fiber.kill` method only exists in later versions of Ruby.
    if instance_methods.include?(:kill)
      # Thread has the same aliases
      alias terminate kill
      alias exit kill
    end
  end

  # TODO: figure out how to do this properly
  # def self.patch_builtin_fiber!
  #   return if ::Fiber.is_a?(FiberMethods)

  #   ::Fiber.singleton_class.prepend(FiberMethods)
  # end
end

class ::Fiber # rubocop:disable Style/Documentation
  extend ::Psyllium::FiberClassMethods
  # This must be prepended so that its implementation of `initialize` is called
  # first.
  include ::Psyllium::FiberInstanceMethods

  # The `Fiber.kill` method only exists in later versions of Ruby.
  if instance_methods.include?(:kill)
    # Thread has the same aliases
    alias terminate kill
    alias exit kill
  end
end
