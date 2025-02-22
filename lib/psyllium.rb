# frozen_string_literal: true

require 'timeout'
require 'forwardable'
require_relative 'psyllium/version'

# Gem to make it easier to work with Fibers.
module Psyllium
  class Error < StandardError; end
  class IncompleteError < Error; end

  # Wrap Exception instances for propagation
  class ExceptionalCompletionError < Error
    def initialize(expt)
      @internal_exception = expt
      super(internal_exception)
    end

    def cause
      @internal_exception
    end
  end

  # Class that wraps a `Fiber` to make it easier to treat it like a `Thread`.
  #
  # Using this class only makes sense when a Fiber scheduler has been set and
  # when the caller does not intend to interact directly with Fiber execution
  # using primitive operations such as `Fiber.resume` and `Fiber.yield`.
  #
  # The internally created `Fiber` cannot be directly accessed. However, many
  # of its methods are forwarded, including `alive?`, `raise`, `kill`,
  # `backtrace`, and `backtrace_locations`. Methods are only forwarded if they
  # are identical to the ones found on `Thread`.
  class Husk
    include Timeout
    extend Forwardable

    def_delegator :@fiber, :alive?
    def_delegator :@fiber, :raise
    def_delegator :@fiber, :kill
    def_delegator :@fiber, :backtrace
    def_delegator :@fiber, :backtrace_locations

    # Start executing a `Husk` instance with the given block.
    #
    # The internal created Fiber will `sleep` for 0 seconds in an attempt to
    # force it into the Fiber scheduler queue. This should allow the created
    # `Husk` instance to be returned immediately. This behavior is dependent on
    # the scheduler implementation.
    #
    # The block will only run if a Fiber scheduler has previously been set.
    # Otherwise an exception will be raised.
    def initialize(&block)
      raise Error.new('No block given') unless block

      @mutex = Thread::Mutex.new
      @value = nil
      @exception = nil
      @fiber = Fiber.schedule do
        @mutex.synchronize do
          # Force a short sleep so that the scheduled Fiber should return
          # immediately. This behavior is dependent on the scheduler
          # implementation.
          sleep(0)
          @value = block.call
        rescue StandardError => e
          @exception = e
        end
      end
    end

    # Waits for Husk to complete, using join, and returns its value. If Husk
    # completed with an exception, raises ExceptionalCompletionError exception,
    # with the original exception as its `cause`.
    def value
      join
      raise ExceptionalCompletionError.new(@exception) if @exception

      @value
    end

    def status
      if alive?
        # The only possible state this can be in is "sleeping" when alive since
        # the Husk lives in the parent Fiber. If the parent Fiber is running,
        # the child Fiber held in `@fiber` cannot (by definition) be running,
        # it must be sleeping.
        'sleeping'
      elsif @exception
        nil
      else
        false
      end
    end

    # Wait until execution completes. Return the Husk instance. If `limit` is
    # reached, returns `nil` instead.
    #
    # `join` may be called more than once.
    def join(limit = nil)
      timeout(limit) do
        # Once this mutex finishes synchronizing, that means the initial
        # calculation is done and we can return `self`, which is the Husk
        # instance.
        @mutex.synchronize do
          self
        end
      end
    rescue Timeout::Error
      # mimic Thread behavior by returning `nil` on timeout.
      nil
    end
  end
end
