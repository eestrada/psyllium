# frozen_string_literal: true

require 'async'
require 'minitest/benchmark'
require_relative 'test_helper'

class BenchPsyllium < Minitest::Benchmark
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
