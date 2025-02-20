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

    def to_s
      internal_exception.to_s
    end
  end

  # Class that wraps a Fiber. Methods are delegated to Fiber when not found in Worker.
  class Husk
    include Timeout
    extend Forwardable

    def_delegator :@fiber, :alive?
    def_delegator :@fiber, :raise

    # Start executing a Husk instance with the given block. Returns the Husk
    # instance as soon as the internal Fiber hits a potentially blocking
    # operation (such as IO).
    #
    # The block will only run if a Fiber scheduler has previously been set.
    def initialize(&block)
      raise Error.new('No block given') unless block

      @mutex = Thread::Mutex.new
      @value = nil
      @exception = nil
      @fiber = Fiber.schedule do
        @mutex.synchronize do
          @value = block.call
        rescue StandardError => e
          @exception = e
        end
      end
    end

    def exceptional_completion?
      complete? && !!@exception
    end

    def check_complete!
      raise IncompleteError.new('Fiber has not completed') unless complete?
    end

    def complete?
      !alive?
    end

    def value
      check_complete!
      @value
    end

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
    # By default this will raise an exception if the Husk instance raised an
    # exception during execution. Setting the keyword argument
    # `raise_exception` to `false` will suppress this behavior. The exception
    # can still be retrieved afterward via the `exception` instance method.
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

  # class methods
  class << self
    def worker(&block)
      raise 'Cannot create worker without block' unless block
    end
  end
end
