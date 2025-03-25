# Psyllium: Makes using Ruby Fibers easier

[![Gem Version](https://badge.fury.io/rb/psyllium.svg?icon=si%3Arubygems)](https://badge.fury.io/rb/psyllium)
[![Main GH Actions workflow](https://github.com/eestrada/psyllium/actions/workflows/main.yml/badge.svg?branch=master)](https://github.com/eestrada/psyllium/actions/workflows/main.yml?query=branch%3Amaster)

> Psyllium \| SIL-ee-um \|
>
> 1. _Dietary_ the seed of a fleawort (especially Plantago psyllium). Mainly
>    used as a supplement to improve dietary fiber consumption.
> 2. _Programming_ a Ruby gem to improve the experience of using Ruby Fiber
>    primitives.

## What is Psyllium?

Psyllium is a library to make it easier to use auto-scheduled Ruby Fibers,
block on their execution, and retrieve their final values.

Ruby 3.0 introduced the Fiber Scheduler interface, making it easier to
use Fibers for concurrent programming. However, native Thread objects still
have several useful methods that Fibers do not have.

By default, the Fiber interface centers around two types of usage:

1. (Before Ruby 3) Explicitly and manually manipulated using `Fiber.yield`,
   `resume`, and `alive?`.
2. (After Ruby 3) Fired off and forgotten about. In essence, left to the
   scheduler to deal with. If you want a final value back you must use some
   separate mechanism to track and retrieve it.

Psyllium adds many of the methods of the Thread class to the builtin Fiber
class, including `start`, `join`, and `value`. This makes it easier to replace
Thread usage with Fiber usage, or to mix and match Thread and Fiber usage
without concern for which concurrency primitive is being used.

Assuming that a Fiber Scheduler is set, Psyllium Fibers can be used in ways
similar to Threads, with a similar interface, and with the added benefit of
much lower memory usage compared to native Threads.

## When to use Psyllium?

If your Ruby application directly manipulates Threads or Thread pools, and
those Threads spend most (or all) of their time waiting on IO, then consider
using Psyllium enhanced Fibers instead of Threads.

Let's imagine a scenario where Psyllium (or Fibers generally) could be useful:

- You have 100 URLs that you need to retrieve values from. Each URL has 1
  second of network latency. Here are some solutions with memory and speed
  tradeoffs:
  - Solution 1: synchronously and serially retrieve values in a loop. You
    receive all 100 responses in 100 seconds using no additional memory.
  - Solution 2: use a thread pool of 10 threads. You receive all 100 responses
    in 10 seconds using 10MB of additional memory (~1MB additional memory per
    Thread).
  - Solution 3: use one thread per URL. You receive all 100 responses in 1
    second using 100MB of additional memory (~1MB additional memory per Thread).
  - Solution 4: use one auto-fiber per URL. You receive all 100 responses in 1
    second using 1.3MB of additional memory ([~13KB of physical memory
    per Fiber](https://bugs.ruby-lang.org/issues/15997)).

## When _not_ to use Psyllium?

Circumstances where you shouldn't use Psyllium (or Fibers generally):

1. Your application is compute heavy. It uses Threads that call out to FFI code
   and release the GVL when doing so (i.e. truly parallel code execution).
2. If you don't have concurrent code at all (i.e. the code must run serially).

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add psyllium
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install psyllium
```

## Usage

Instead of doing the following in your code:

```ruby
thread1 = Thread.start { long_running_io_operation_with_result1() }
thread2 = Thread.start { long_running_io_operation_with_result2() }

thread1.join
thread2.join

puts 'thread1 ended with an exception' if thread1.status.nil?
puts 'thread2 ended without an exception' if thread2.status == false

# `value` implicitly calls `join`, so the explicit `join` calls above are
# not strictly necessary.
result1 = thread1.value
result2 = thread2.value
```

You can now do this:

```ruby
# Adds new methods to Fiber
require 'psyllium'

# Calls to `Fiber.start` will fail if no scheduler is set beforehand.
Fiber.set_scheduler(SomeSchedulerImplementation.new)

fiber1 = Fiber.start { long_running_io_operation_with_result1() }
fiber2 = Fiber.start { long_running_io_operation_with_result2() }

fiber1.join
fiber2.join

puts 'fiber1 ended with an exception' if fiber1.status.nil?
puts 'fiber2 ended without an exception' if fiber2.status == false

# `value` implicitly calls `join`, so the explicit `join` calls above are
# not strictly necessary.
result1 = fiber1.value
result2 = fiber2.value
```

## Development

After checking out the repo, run `bin/setup` to install dependencies.
Then, run `rake test` to run the tests.
You can also run `bin/console` for an interactive prompt
that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.
To release a new version, update the version number in `version.rb`,
and then run `bundle exec rake release`, which will create a git tag for the version,
push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at: <https://github.com/eestrada/psyllium>
