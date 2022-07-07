# Fennel Async

A library for asynchronous programming in Fennel and Lua.

This library provides facilities for asynchronous programming implemented in pure Fennel, as well as a set of synchronization primitives.
Either [luasocket](https://w3.impa.br/~diego/software/luasocket) or [luaposix](http://luaposix.github.io/luaposix/) is required for this library to work.
With `luasocket` the `tcp` module becomes available, and asynchronous socket interface is provided, where sockets act as channels.

## Installation

Grab the [async.fnl](https://gitlab.com/andreyorst/fennel-async/-/raw/main/async.fnl) file and put it into your project or somewhere in `fennel-path`.
Alternatively, compile this file to Lua using `make` and place somewhere under `LUA_PATH`.

## Design

This library comes in one file, which itself is a namespace and a callable function.
While this library provides ways to run tasks collaboratively, it's important to understand that tasks are not ran in background or in a separate OS thread, because Lua doesn't support these facilities.
So, functions provided by the `async` module are implemented in a way that creates a feeling of running in background, even though it's not.
Threads are implemented with Lua's coroutines, and are maintained by the scheduler.

To start a thread, call the `queue` function, or the module itself with a function as an argument:

``` fennel
Welcome to Fennel 1.0.0 on Lua 5.4!
Use ,help to see available commands.
>> (local async (require :async))
nil
>> (async (fn [] (print "a new thread")))
a new thread
#<promise: 0x55e4974856f0>
```

As can be seen, when creating a new thread, which just prints a message, the message is immediately displayed, and a `promise` is returned.
It may seem like if `print` ran in background, but in reality, threads are ran just after creation.

Here are all actions that, when done on the main thread, cause asynchronous threads to advance:

- Spawning a new thread with `async` or `async.queue`;
- `deliver`ing or `await`ing a `promise`;
- `send`ing a task to agent or `deref`erencing an `agent`;
- when a value was `put` or `take`n from a `chan`nel;
- `sleep`ing.

The `promise` returned by the `async` function is one of the synchronization primitives, that allows us to `await` for event to happen.
For example, we can create a thread that sleeps a certain amount of time, and prints a message:

``` fennel
>> (async (fn [] (async.sleep 1000) (print "slept 1s")))
#<promise: 0x55e49752ec70>
```

This time no message was displayed, because the thread was immediately suspended.
To run the thread, we can either use the `async.run` function, which runs all threads, or `await` on a promise of the thread.
But since we didn't store the promise, we can't `await` on it.

``` fennel
>> (async.run)
slept 1s
nil
```

If the `run` function wasn't executed immediately, the message will displayed right away, because the thread slept longer than one second, and was ready to be resumed.
As a more complete example, consider three threads that sleep different amount of time:

``` fennel
>> (let [t1 (async (fn [] (async.sleep 100) (print 1)))
         t2 (async (fn [] (async.sleep 300) (print 3)))
         t3 (async (fn [] (async.sleep 200) (print 2)))]
     (async.await t2))
1
2
3
nil
```

We `await` for the longest sleeping thread, which causes all threads to run simultaneously.

If we measure the execution time and CPU time for this task it can be seen that CPU wasn't doing a lot during sleep:

``` fennel
>> (local socket (require :socket))
nil
>> (let [exec-start (socket.gettime)
         cpu-start (os.clock)
         t1 (async (fn [] (async.sleep 1000)))
         t2 (async (fn [] (async.sleep 3000)))
         t3 (async (fn [] (async.sleep 2000)))]
     (async.await t2)
     (print "CPU time:" (- (os.clock) cpu-start))
     (print "exec time:" (- (socket.gettime) exec-start)))
CPU time:	0.000552
exec time:	3.0004191398621
```

More examples can be found at the project's [wiki](https://gitlab.com/andreyorst/fennel-async/-/wikis/home).

## Documentation

The documentation is auto-generated with [Fenneldoc](https://gitlab.com/andreyorst/fenneldoc) and can be found [here](doc/async.md).

## Contributing

Please do.
You can report issues or feature request at [project's GitLab repository](https://gitlab.com/andreyorst/fennel-async).
Consider reading [contribution guidelines](CONTRIBUTING.md) beforehand.
