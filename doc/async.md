# Async.fnl (v0.0.1)
A library for asynchronous programming for the Fennel language and Lua
runtime.

This library provides facilities for asynchronous programming by
implementing a coroutine scheduler and various synchronization
primitives.

To use this library require its main module and use it as the function
to spawn threads:

``` fennel
(local async (require :async))

(local p (async.promise))
(local thread-1 (async (fn [] (async.sleep 400) (async.deliver p 42))))
(local thread-2 (async (fn [] (print (async.await p 100 :not-delivered)))))
(print (async.await p))
```

In the example above a promise is created and two threads are spawned.
The first thread sleeps for 400ms and delivers a promise.  The second
thread awaits for promise with a timeout of 100ms and prints
`not-delivered` because the promise wasn't realized yet.  Lastly, the
promise is awaited in the main thread, blocking the execution, while
threads are cooperating. As a result, `42` is printed.

For more examples see the project's [wiki](https://gitlab.com/andreyorst/fennel-async/-/wikis/home).

**Table of contents**

- [`queue`](#queue)
- [`run`](#run)
- [`await`](#await)
- [`sleep`](#sleep)
- [`promise`](#promise)
- [`deliver`](#deliver)
- [`zip`](#zip)
- [`alt`](#alt)
- [`agent`](#agent)
- [`send`](#send)
- [`agent-error`](#agent-error)
- [`chan`](#chan)
- [`put`](#put)
- [`take`](#take)
- [`buffer`](#buffer)
- [`dropping-buffer`](#dropping-buffer)
- [`error!`](#error)
- [`park`](#park)
- [`restart-agent`](#restart-agent)

## `queue`
Function signature:

```
(queue task)
```

Enqueue a `task` and return a promise object for that task.  The
module table is an alias to this function.

## `run`
Function signature:

```
(run mode)
```

Run all tasks from the task queue according to the `mode`.

Supported modes:

- `:once` - run each task once.
- `:tasks` - run until all tasks are completed.
  May block forever, if some tasks never finish.

## `await`
Function signature:

```
(await p timeout timeout-val)
```

Get the value of a promise or an agent.

Parks/blocks a thread if promise `p` wasn't delivered. If `timeout` is
a number, sleeps this amount of milliseconds until the value is
delivered.  If a value wasn't delivered, returns the `timeout-val`.
Doesn't block/park when polling agents.

## `sleep`
Function signature:

```
(sleep ms)
```

Sleep specified amount of `ms`

If invoked in a task, puts the thread in a sleeping state and parks.
Otherwise, if invoked in the main thread, blocks the execution and
runs the tasks.  If luasocket is available, blocking is done via
`socket.sleep`.  If luaposix is available, blocking is done via
`posix.nanosleep`.  Otherwise, a busy loop is used.

## `promise`
Function signature:

```
(promise)
```

Create a promise object.

A promise is a reference type that can be changed by using the
[`deliver`](#deliver) function and observed with the [`await`](#await) function or the
`deref` method.  Once delivered, the value can no longer be changed by
any other calls to [`deliver`](#deliver).

## `deliver`
Function signature:

```
(deliver p val)
```

Deliver the value `val` to the promise `p`.

## `zip`
Function signature:

```
(zip ...)
```

Await for all promises.

Returns a table with promise results and the number of promises under
the `:n` key to keep any possible `nil` values.

## `alt`
Function signature:

```
(alt ...)
```

Wait for several promises simultaneously, return the value of the
first one ready. Argument order doesn't matter, because the poll order
is shuffled.  For a more non deterministic outcome, call
`math.randomseed` with some seed.

## `agent`
Function signature:

```
(agent data)
```

Create an agent with the `data` as the agent's state.

Agents support non-blocking operations via the [`send`](#send) function.  When
reading the agent's state with the `deref` method or [`await`](#await) function,
the execution is never blocked/parked.  If an error happened during
the execution of the agent's task, dereferencing the agent may throw
an error.  Use [`agent-error`](#agent-error) function to check if there were errors
during execution.  Use [`restart-agent`](#restart-agent) to repair a failed agent.

## `send`
Function signature:

```
(send agent f ...)
```

Send a task to agent's task queue, modifying `agent` state by
calling `f` with current agent state as its first argument.

See [`agent`](#agent) on how to create and use agents.

## `agent-error`
Function signature:

```
(agent-error agent)
```

Return the error object from the `agent` if the agent failed.
Otherwise returns nil.

## `chan`
Function signature:

```
(chan buffer-or-size xform)
```

Create a channel with a set buffer and an optional transforming function.

The `buffer-or-size` argument can be a number for creating a fixed
buffer, or a buffer object.  The `xform` parameter is a function that
is invoked on the element before putting it to the channel.  The
result of this function will be put into the channel instead.  To
ignore a value, `xform` must return `nil`.  Channels themselves can't
contain nils.

## `put`
Function signature:

```
(put chan val)
```

Put a value `val` to a channel `chan`.

## `take`
Function signature:

```
(take chan timeout timeout-val)
```

Take a value from a channel `chan`.  If `timeout` is a number,
sleeps this amount of milliseconds until the value is delivered.  If a
value wasn't delivered, returns the `timeout-val`.

## `buffer`
Function signature:

```
(buffer size)
```

Create a buffer of set `size`.

When the buffer is full, puts will park/block the thread.

## `dropping-buffer`
Function signature:

```
(dropping-buffer size)
```

Create a dropping buffer of set `size`

When the buffer is full puts will succeed, but the value will be
dropped.

## `error!`
Function signature:

```
(error! p err)
```

Set the promise `p` to error state, with `err` set as error cause.
Does nothing if promise was already delivered.

## `park`
Function signature:

```
(park)
```

Manually park the current thread.

Does nothing on the main thread.

## `restart-agent`
Function signature:

```
(restart-agent agent val)
```

Restart the `agent` with a given `val`.


---

Copyright (C) 2021 Andrey Listopadov

License: [MIT](https://gitlab.com/andreyorst/fennel-async/-/raw/master/LICENSE)


<!-- Generated with Fenneldoc v0.1.9-dev
     https://gitlab.com/andreyorst/fenneldoc -->
