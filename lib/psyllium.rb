# frozen_string_literal: true

require 'delegate'
require 'timeout'
require_relative 'psyllium/version'

# Gem to make it easier to work with Fibers.
module Psyllium
  class Error < StandardError; end
  class IncompleteError < Error; end

  # Class that wraps a Fiber. Methods are delegated to Fiber when not found in Worker.
  class Husk
    include Timeout
    extend Forwardable
    def_delegator :@fiber, :alive?
    def_delegator :@fiber, :raise

    # Start executing a Husk instance with the given block.
    #
    # The block will only run if a Fiber scheduler has been set.
    def initialize(&block)
      raise Error.new('No block given') unless block

      @_is_complete = false
      @value = nil
      @exception = nil
      @fiber = Fiber.schedule do
        @value = block.call
        @_is_complete = true
      rescue StandardError => e
        @exception = e
        @_is_complete = true
      end
    end

    def exceptional_completion?
      complete? && !!@exception
    end

    def check_complete!
      raise IncompleteError.new('Fiber has not completed') unless complete?
    end

    def complete?
      @_is_complete
    end

    def value
      check_complete!
      @value
    end

    def exception
      check_complete!
      @exception
    end

    # Wait until execution completes.
    #
    # Can be given a `wait_timeout` value, in which case execution will end
    # early with a TimeoutError. By default, this will wait indefinitily for
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
        loop do
          # by sleeping, we force the Fiber scheduler to run.
          sleep(0) while alive?

          raise exception if raise_exception && exceptional_completion?

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
