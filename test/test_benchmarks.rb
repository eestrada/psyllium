# frozen_string_literal: true

require 'async'
require 'minitest/benchmark'
require_relative 'test_helper'

class BenchPsyllium < Minitest::Benchmark
  # At its peak, `n` for this benchmark is equal to 10000. Each Fiber created
  # sleeps for 0.1 seconds, so if this scaled linearly it would take 1000
  # seconds. In reality, this takes less than 1 second to join 10000 Fibers.
  #
  # The time does increase with more Fibers due to unrelated overhead. For
  # example, allocating memory for Fiber instances takes time, even though this
  # is unrelated to the actual sleep time.
  def bench_joining_multiple_fibers_is_roughly_big_o_constant
    Async do
      assert_performance_constant(0.9999) do |n|
        sleep_time = 0.1
        fibers = n.times.map { Fiber.start { sleep(sleep_time) } }
        fibers.each(&:join)
      end
    end
  end
end
