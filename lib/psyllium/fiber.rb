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

  # Meant to be used with `extend` on Fiber class.
  module FiberClassMethods
    def start(&block)
      raise ArgumentError.new('No block given') unless block

      fiber = new(blocking: false, &block)
      fiber.resume
      fiber
    end
  end

  # A module meant to extend the builtin Fiber class to make it easier to use
  # in a more Thread-like manner.
  module FiberInstanceMethods
    # Override Fiber initialization to track value and exception, and to make
    # Fiber joinable.
    def initialize(**kwargs, &block)
      raise ArgumentError.new('No block given') unless block

      @mutex = Thread::Mutex.new
      @started = false
      @value = nil
      @exception = nil
      @joined = false
      super do |*args|
        @mutex.synchronize do
          @started = true
          @value = block.call(*args)
        rescue StandardError => e
          @exception = e
        ensure
          @joined = true
        end
      end
    end

    # Waits for Fiber to complete, using join, and returns its value. If Fiber
    # completed with an exception, raises `ExceptionalCompletionError`, with
    # the original exception as its `cause`.
    def value
      join
      raise ExceptionalCompletionError.new(@exception) if @exception

      @value
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
      elsif @exception
        nil
      else
        false
      end
    end

    # Mimic Thread `stop?` method.
    #
    # Return `true` if sleeping or completed.
    def stop?
      status != 'run'
    end

    # Wait until execution completes. Return the Fiber instance. If `limit` is
    # reached, returns `nil` instead.
    #
    # `join` may be called more than once.
    def join(limit = nil) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/AbcSize
      return self if @joined
      raise FiberError.new('Cannot join self') if self == ::Fiber.current
      raise FiberError.new('Cannot join when calling Fiber is blocking') if ::Fiber.current.blocking?
      raise FiberError.new('Cannot join when called Fiber is blocking') if blocking?
      raise FiberError.new('Cannot join without Fiber scheduler set') unless ::Fiber.scheduler
      raise FiberError.new('Cannot join unstarted Fiber') unless @started

      Timeout.timeout(limit) do
        # Once this mutex finishes synchronizing, that means the initial
        # calculation is done and we can return `self`, which is the Fiber
        # instance.
        @mutex.synchronize do
          return self
        end
      end
    rescue Timeout::Error
      # mimic Thread behavior by returning `nil` on timeout.
      nil
    end
  end

  # Inherits from the builtin Fiber class, and adds additional functionality to
  # make it behave more like a Thread.
  class Fiber < ::Fiber
    extend ::Psyllium::FiberClassMethods
    # This must be prepended so that its implementation of `initialize` is called
    # first.
    prepend ::Psyllium::FiberInstanceMethods

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
  prepend ::Psyllium::FiberInstanceMethods

  # The `Fiber.kill` method only exists in later versions of Ruby.
  if instance_methods.include?(:kill)
    # Thread has the same aliases
    alias terminate kill
    alias exit kill
  end
end
