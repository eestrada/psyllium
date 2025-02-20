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
    attr_reader :internal_exception

    def initialize(expt)
      @internal_exception = expt
      super(internal_exception)
    end
  end

  # Class that wraps a `Fiber` to make it easier to treat it like a `Thread` or
  # some sort of Future or Promise.
  #
  # Using this class only makes sense when a Fiber scheduler has been set and
  # when the caller does not intend to interact directly with Fiber execution
  # using primitive operations such as `Fiber.resume` and `Fiber.yield`.
  #
  # The internally created `Fiber` cannot be directly accessed. However, it is
  # possible to check if it is `alive?` using `Husk.alive?` and to forcefully
  # raise an exception within it by calling `Husk.raise`.
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

    # Return `true` if the block completed executing, `false` otherwise.
    def complete?
      !alive?
    end

    # Raises an `Psyllium::IncompleteError` exception if execution of the block
    # has not completed yet.
    #
    # Otherwise, does nothing.
    def check_complete!
      raise IncompleteError unless complete?
    end

    # Return the value returned from the given block. May be `nil` either
    # because the given block returned `nil` or because the block raised an
    # exception. Use `exceptional_completion?` to check if the block completed
    # exceptionally.
    #
    # Raises an `Psyllium::IncompleteError` exception if execution of the block
    # has not completed yet.
    def value
      check_complete!
      raise ExceptionalCompletionError.new(exception) if exceptional_completion?

      @value
    end

    # Return `true` if the block completed exceptionally, `false` otherwise.
    #
    # Raises an `Psyllium::IncompleteError` exception if execution of the block
    # has not completed yet.
    def exceptional_completion?
      check_complete!
      !!@exception
    end

    # Return the exception raised from the given block. Returns `nil` if no
    # exception was raised.
    #
    # Raises an `Psyllium::IncompleteError` exception if execution of the block
    # has not completed yet.
    def exception
      check_complete!
      @exception
    end

    # Wait until execution completes. Return the value of the executed block,
    # if it completed successfully.
    #
    # Can be given a `wait_timeout` value, in which case execution will end
    # early with a TimeoutError. By default, this will wait indefinitely for
    # execution to complete.
    #
    # By default this will raise an `ExceptionalCompletionError` exception if
    # the Husk instance raised an exception during execution. Setting the
    # keyword argument `raise_exception` to `false` will suppress this
    # behavior. The exception (if raised) can still be retrieved afterward via
    # the `exception` instance method.
    #
    # `join` may be called more than once.
    def join(wait_timeout = nil, raise_exception: true)
      timeout(wait_timeout) do
        @mutex.synchronize do
          raise ExceptionalCompletionError.new(exception) if raise_exception && exceptional_completion?

          value
        end
      end
    end
  end
end
