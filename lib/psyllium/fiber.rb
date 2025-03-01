# frozen_string_literal: true

require 'timeout'

module Psyllium
  # Wrap Exception instances for propagation
  class ExceptionalCompletionError < FiberError
    def initialize(expt)
      @internal_exception = expt
      super(internal_exception)
    end

    def cause
      @internal_exception
    end
  end

  # A module meant to extend the builtin Fiber class to make it easier to use
  # in a more Thread-like manner.
  module Fiber
    # Override Fiber initialization to possibly track value and exception.
    def initialize(blocking: false, storage: true, &block)
      raise ArgumentError.new('No block given') unless block

      if blocking
        super
      else
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
          end
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
    # `abort` status is never returned because Fiber does not have a state like
    # this that is detectable or observable.
    #
    # `run` will only be returned if this is called on `Fiber.current`.
    def status
      if self == Fiber.current
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
      raise FiberError.new('Cannot join without Fiber scheduler set') unless ::Fiber.current_scheduler
      raise FiberError.new('Cannot join unstarted Fiber') unless @started

      Timeout.timeout(limit) do
        # Once this mutex finishes synchronizing, that means the initial
        # calculation is done and we can return `self`, which is the Husk
        # instance.
        @mutex.synchronize do
          @joined = true
          self
        end
      end
    rescue Timeout::Error
      # mimic Thread behavior by returning `nil` on timeout.
      nil
    end
  end
end

class ::Fiber
  # This must be prepended so that its implementation of `initialize` is called
  # first.
  prepend ::Psyllium::Fiber
end
