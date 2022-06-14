;;; async.fnl

(comment
 MIT License

 Copyright (c) 2022 Andrey Listopadov

 Permission is hereby granted‚ free of charge‚ to any person obtaining a copy
 of this software and associated documentation files (the "Software")‚ to deal
 in the Software without restriction‚ including without limitation the rights
 to use‚ copy‚ modify‚ merge‚ publish‚ distribute‚ sublicense‚ and/or sell
 copies of the Software‚ and to permit persons to whom the Software is
 furnished to do so‚ subject to the following conditions：

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS"‚ WITHOUT WARRANTY OF ANY KIND‚ EXPRESS OR
 IMPLIED‚ INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY‚
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM‚ DAMAGES OR OTHER
 LIABILITY‚ WHETHER IN AN ACTION OF CONTRACT‚ TORT OR OTHERWISE‚ ARISING FROM‚
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.)

(local {:create c/create
        :resume c/resume
        :yield c/yield
        :status c/status
        :running c/running}
  coroutine)

(local {:insert t/insert
        :remove t/remove
        :concat t/concat}
  table)

(local t/unpack (or table.unpack _G.unpack))

(fn t/pack [...] (doto [...] (tset :n (select "#" ...))))

(fn t/append [t val]
  (doto t (tset (+ 1 (length t)) val)))

(fn pp [self]
  (.. "#<" (tostring self) ">"))


;;; Optional dependencies

(local socket
  (match (pcall require :socket)
    (true socket) socket
    _ nil))

(local posix
  (match (pcall require :posix)
    (true posix) posix
    _ nil))


;;; Clock

(local clock
  (if (?. socket :gettime)
      socket.gettime
      (?. posix :clock_gettime)
      (let [gettime posix.clock_gettime]
        #(let [(s ms) (gettime)]
           (tonumber (.. s "." ms))))
      (?. os :clock) os.clock
      (error "no clock function available on this system")))


;;; Queues

(fn fifo []
  ;; Agent queue.  Task order is deterministic first in first out
  (setmetatable
   []
   {:__index
    {:put (fn [self task] (t/insert self (+ 1 (length self)) task))
     :remove (fn [self task]
               (var done false)
               (each [i t (ipairs self) :until done]
                 (when (= t task)
                   (table.remove self i)
                   (set done true))))}}))

(fn queue []
  ;; default queue.  Task order is based on Lua hashing function
  (setmetatable
   {}
   {:__index
    {:put (fn [self task] (tset self task task))
     :remove (fn [self task] (tset self task nil))}}))


;;; Scheduler

(local async {:io {}})

(local scheduler
  {:queue (queue)
   :agent-queue (fifo)})

(local park-condition
  (setmetatable {} {:__name "park" :__fennelview pp}))

(local sleep-condition
  (setmetatable {} {:__name "sleep" :__fennelview pp}))

(local internal-sleep-time 0.01)

(fn scheduler.schedule [queue task]
  ;; Schedule a task and return a promise object
  (let [p (async.promise)
        c (c/create (fn [] (async.deliver p (task))))]
    (queue:put {:state :suspended :promise p :task c})
    p))

(fn suspend! [thread]
  ;; Set thread's state to the suspended state
  (doto thread
    (tset :wake-time nil)
    (tset :state :suspended)))

(fn sleep! [thread wake-time]
  ;; Set thread's state to the sleeping state
  (doto thread
    (tset :wake-time wake-time)
    (tset :state :sleep)))

(local m/min math.min)
(fn set-shortest-time! [sleep-time]
  ;; Sets the shortest time scheduler can spent sleeping before going
  ;; to the next iteration.
  (set scheduler.shortest-sleep-time
       (match scheduler.shortest-sleep-time
         t (m/min t sleep-time)
         _ sleep-time)))

(fn do-task [queue {: task : promise &as thread}]
  ;; Execute a given task once and change its state
  (match (c/resume task)
    (true sleep-condition wake-time)
    (let [sleep-time (- wake-time (clock))
          sleep-time (if (< sleep-time 0) 0 sleep-time)]
      (sleep! thread wake-time)
      (set-shortest-time! sleep-time))
    (true park-condition)
    (do (set-shortest-time! 0)
        (suspend! thread))
    (true _)
    (if (= :dead (c/status task))
        (queue:remove thread)
        (do (suspend! thread)
            (set-shortest-time! 0)))
    (false msg) (do (queue:remove thread)
                    (async.error! promise msg)
                    (io.stderr:write
                     "error in " (tostring task) ": " (tostring msg) "\n"))))

(fn do-sleep [queue thread]
  ;; Check if any of the tasks can be waked up based on current time
  (let [now (clock)
        {: wake-time} thread
        sleep-time (- wake-time now)]
    (if (>= now wake-time)
        (do-task queue thread)
        (set-shortest-time! sleep-time))))

(fn scheduler.run []
  ;; Run each task from the task queue.  Returns `true` if there are
  ;; remaining tasks to execute, and amount of time spent executing.
  (set scheduler.shortest-sleep-time nil)
  (let [start-time (clock)
        {: queue : agent-queue} scheduler]
    (each [_ queue (ipairs [queue agent-queue])]
      (each [_ thread (pairs queue)]
        (set scheduler.current-thread thread)
        (match thread.state
          :suspended (do-task queue thread)
          :sleep (do-sleep queue thread)))
      (set scheduler.current-thread nil))
    (values (if (or (next queue)
                    (next agent-queue))
                true
                false)
            (- (clock) start-time)
            (match scheduler.shortest-sleep-time
              (where t (> t 0)) t))))

(fn async.run [mode]
  "Run all tasks from the task queue according to the `mode`.

Supported modes:

- `:once` - run each task once.
- `:tasks` - run until all tasks are completed.
  May block forever, if some tasks never finish."
  (var run? true)
  (if (or (= mode :tasks) (= nil mode))
      (when (not scheduler.current-thread)
        (while run?
          (let [(more? _ sleep-time) (scheduler.run)]
            (set run? more?)
            (when sleep-time
              (scheduler.sleep sleep-time true)))))
      (= :once mode)
      (when (not scheduler.current-thread)
        (let [(more? _ sleep-time) (scheduler.run)]
          (set run? more?)
          (when sleep-time
            (scheduler.sleep sleep-time true))))
      (error (.. "unsupported mode" (tostring mode)))))

(fn async.park []
  "Manually park the current thread.

Does nothing on the main thread."
  (when scheduler.current-thread
    (c/yield park-condition)))

(fn async.queue [task]
  "Enqueue a `task` and return a promise object for that task.  The
module table is an alias to this function."
  (let [p (scheduler.schedule scheduler.queue task)]
    (when (not scheduler.current-thread)
      (scheduler.run))
    p))


;;; Sleep

(local sleep
  (if socket #(socket.sleep $)
      posix (let [modf math.modf]
              #(let [(s ms) (modf $)]
                 (posix.nanosleep s (* 1000000 1000 ms))))
      ;; otherwise do a busy sleep, as there's no good way to detect
      ;; what's supported with os.execute (e.g. there's no sleep on
      ;; Windows). This chews the CPU, of course.
      #(let [end (+ (clock) $)]
         (while (< (clock) end)
           nil))))

(fn scheduler.sleep [s block?]
  (assert (= :number (type s)) "time must be a number")
  (if scheduler.current-thread
      (c/yield sleep-condition (+ (clock) s))
      (do
        (var slept 0)
        (var run? true)
        (while (and (< slept s) run?)
          (let [(more? time-spent sleep-time) (scheduler.run)]
            (set run? more?)
            (set slept (+ slept time-spent (or (and block? sleep-time) 0)))
            (when (and block? sleep-time)
              (sleep sleep-time))))
        (when (< slept s)
          (sleep (- s slept))))))

(fn async.sleep [ms]
  "Sleep specified amount of `ms`

If invoked in a task, puts the thread in a sleeping state and parks.
Otherwise, if invoked in the main thread, blocks the execution and
runs the tasks.  If luasocket is available, blocking is done via
`socket.sleep`.  If luaposix is available, blocking is done via
`posix.nanosleep`.  Otherwise, a busy loop is used."
  (scheduler.sleep (/ ms 1000) true))


;;; Promise

(local promise {})

(fn promise.deref [self timeout timeout-val]
  (when timeout
    (assert (= :number (type timeout)) "timeout must be a number"))
  (when (= self.state :error)
    (error self.error))

  (let [coroutine? scheduler.current-thread
        timeout (and timeout (/ timeout 1000))]
    (var slept 0)
    (if timeout
        (while (and (not self.ready) (< slept timeout))
          (let [start (clock)]
            (if coroutine?
                (c/yield sleep-condition (+ start internal-sleep-time))
                (scheduler.sleep internal-sleep-time false))
            (set slept (+ slept (- (clock) start)))))
        (while (not self.ready)
          (if coroutine?
              (c/yield park-condition)
              (async.run :once))))
    (if (and timeout (>= slept timeout) (not self.ready))
        timeout-val
        self.val)))

(fn async.promise []
  "Create a promise object.

A promise is a reference type that can be changed by using the
`deliver' function and observed with the `await' function or the
`deref` method.  Once delivered, the value can no longer be changed by
any other calls to `deliver'."
  (setmetatable
   {:val nil
    :ready false}
   {:__name "promise"
    :__fennelview pp
    :__index promise}))


;;; Agent

(local agent {})

(fn agent.deref [self]
  (when (= self.state :error)
    (error self.error))
  (async.run :once)
  self.val)

(fn async.send [agent f ...]
  "Send a task to agent's task queue, modifying `agent` state by
calling `f` with current agent state as its first argument.

See `agent' on how to create and use agents."
  (assert (not= agent.state :error) "agent error")
  (let [args (t/pack ...)]
    (scheduler.schedule
     scheduler.agent-queue
     (fn []
       (match (pcall f agent.val (t/unpack args 1 args.n))
         (true res) (set agent.val res)
         (false msg) (doto agent
                       (tset :state :error)
                       (tset :error msg)
                       (tset :val nil)))))
    (when (not scheduler.current-thread)
      (async.run :once))
    nil))

(fn async.agent-error [agent]
  "Return the error object from the `agent` if the agent failed.
Otherwise returns nil."
  (match agent.state
    :error agent.error))

(fn async.restart-agent [agent val]
  "Restart the `agent` with a given `val`."
  (doto agent
    (tset :val val)
    (tset :state :restarted)
    (tset :error nil)))

(fn async.agent [data]
  "Create an agent with the `data` as the agent's state.

Agents support non-blocking operations via the `send' function.  When
reading the agent's state with the `deref' method or `await' function,
the execution is never blocked/parked.  If an error happened during
the execution of the agent's task, dereferencing the agent may throw
an error.  Use `agent-error' function to check if there were errors
during execution.  Use `restart-agent' to repair a failed agent."
  (setmetatable {:val data
                 :error nil
                 :state :running}
                {:__name "agent"
                 :__fennelview pp
                 :__index agent}))


;;; Buffers

(fn async.buffer [size]
  "Create a buffer of set `size`.

When the buffer is full, returns `false'.  Taking from the buffer must
return `nil', if the buffer is empty.

#Examples

The simplest implementation of a fixed-size buffer defines the `put'
method to check if the length of the buffer is less than the specified
size. The `take' method checks if the length of the buffer is empty.
Putting a value to the buffer must never block.

```fennel
(fn blocking-buffer [size]
  {:put (fn [buffer val]
          (if (< (length buffer) size)
              (do (table.insert buffer val)
                  true)
              false))
   :take (fn [buffer]
           (when (> (length buffer) 0)
             (table.remove buffer 1)))})

(let [b (blocking-buffer 2)]
  (assert-is (b:put 42))
  (assert-is (b:put 27))
  ;; can't put any more values
  (assert-not (b:put 72))

  (assert-eq 42 (b:take))
  (assert-eq 27 (b:take))
  ;; buffer is empty, nothing to return
  (assert-eq nil (b:take)))
```

By design of this library, buffers can't contain `nil' values, and
`nil' is reserved as a marker of an empty buffer."
  (and size (assert (= :number (type size)) "size must be a number"))
  (assert (not (: (tostring size) :match "%.")) "size must be integer")
  (setmetatable {:size (or size math.huge)}
                {:__name "buffer"
                 :__fennelview pp
                 :__index {:put (fn [buffer val]
                                  (let [len (length buffer)]
                                    (if (< len buffer.size)
                                        (do (tset buffer (+ 1 len) val)
                                            true)
                                        false)))
                           :take (fn [buffer]
                                   (when (> (length buffer) 0)
                                     (t/remove buffer 1)))}}))

(fn async.dropping-buffer [size]
  "Create a dropping buffer of set `size`

When the buffer is full puts will succeed, but the value will be
dropped.

# Examples

Putting a value into dropping buffer always succeeds, because the
value can be dropped if the buffer is full. Here's the simplest
implementation of a dropping buffer:

```fennel
(fn dropping-buffer [size]
  {:put (fn [buffer val]
          (when (< (length buffer) size)
            (table.insert buffer val))
          true)
   :take (fn [buffer]
           (when (> (length buffer) 0)
             (table.remove buffer 1)))})

(let [b (dropping-buffer 2)]
  (assert-is (b:put 42))
  (assert-is (b:put 27))
  ;; can't put any more values, but put is successful
  (assert-is (b:put 72))

  (assert-eq 42 (b:take))
  (assert-eq 27 (b:take))
  ;; buffer is empty, nothing to return
  (assert-eq nil (b:take)))
```

See `buffer` for more info."
  (assert (= :number (type size)) "size must be a number")
  (assert (not (: (tostring size) :match "%.")) "size must be integer")
  (setmetatable {:size size}
                {:__name "dropping buffer"
                 :__fennelview pp
                 :__index {:put (fn [buffer val]
                                  (when (< (length buffer) size)
                                    (tset buffer (+ 1 (length buffer)) val))
                                  true)
                           :take (fn [buffer]
                                   (when (> (length buffer) 0)
                                     (t/remove buffer 1)))}}))


;;; Channels

(fn put [buffer val]
  (assert (not= nil val) "value must not be nil")
  (while (not (buffer:put val))
    (if scheduler.current-thread
        (c/yield park-condition)
        (async.run :once))))

(fn async.put [chan val]
  "Put a value `val` to a channel `chan`."
  (let [{: buffer : xform} chan]
    (if xform
        (match (xform val)
          val* (put buffer val*))
        (put buffer val))
    (async.run :once)
    true))

(fn async.take [chan timeout timeout-val]
  "Take a value from a channel `chan`.  If `timeout` is a number,
sleeps this amount of milliseconds until the value is delivered.  If a
value wasn't delivered, returns the `timeout-val`."
  (var slept 0)
  (let [coroutine? scheduler.current-thread
        buffer chan.buffer
        timeout (and timeout (/ timeout 1000))
        loop (if timeout
                 (fn loop [val]
                   (if (and (= nil val) (< slept timeout))
                       (let [start (clock)]
                         (if coroutine?
                             (c/yield sleep-condition (+ start internal-sleep-time))
                             (scheduler.sleep internal-sleep-time false))
                         (set slept (+ slept (- (clock) start)))
                         (loop (buffer:take)))
                       val))
                 (fn loop [val]
                   (if (= nil val)
                       (do (if coroutine?
                               (c/yield park-condition)
                               (async.run :once))
                           (loop (buffer:take)))
                       val)))
        res (match (loop (buffer:take))
              val val
              (where nil (and timeout (>= slept timeout))) timeout-val
              _ nil)]
    (async.run :once)
    res))

(fn async.chan [buffer-or-size xform]
  "Create a channel with a set buffer and an optional transforming function.

The `buffer-or-size` argument can be a number for creating a fixed
buffer, or a buffer object.  The `xform` parameter is a function that
is invoked on the element before putting it to the channel.  The
result of this function will be put into the channel instead.  To
ignore a value, `xform` must return `nil`.  Channels themselves can't
contain nils.

Buffer is an object with two methods `put' and `take'. When the put
operation can be preformed, the `put' method should put the value into
the buffer and return `true'. Otherwise, it should return `false' and
not perform any actions. Similarly, when the value can't be taken from
the buffer, the `take' method must return `nil', and a value
otherwise. Buffers can't have nils as values. See `buffer` and
`dropping-buffer` for examples."
  (setmetatable {:buffer (match (type buffer-or-size)
                           :number (async.buffer buffer-or-size)
                           :table buffer-or-size
                           :nil (async.buffer)
                           _ (error (.. "wrong buffer-or-size type. Expected buffer or int, got: " _)))
                 : xform}
                {:__name "channel"
                 :__fennelview pp
                 :__index {:put async.put
                           :take async.take}}))


;;; Operations on reference types

(fn async.deliver [p val]
  "Deliver the value `val` to the promise `p`."
  (let [res (if p.ready
                false
                (do (doto p
                      (tset :val val)
                      (tset :ready true))
                    true))]
    (when (not scheduler.current-thread)
      (async.run :once))
    res))

(fn async.zip [...]
  "Await for all promises.

Returns a table with promise results and the number of promises under
the `:n` key to keep any possible `nil` values."
  (let [promises (t/pack ...)]
    (for [i 1 promises.n]
      (tset promises i (: (. promises i) :deref)))
    promises))

(fn async.await [p timeout timeout-val]
  "Get the value of a promise or an agent.

Parks/blocks a thread if promise `p` wasn't delivered. If `timeout` is
a number, sleeps this amount of milliseconds until the value is
delivered.  If a value wasn't delivered, returns the `timeout-val`.
Doesn't block/park when polling agents."
  (match p
    {: deref} (p:deref timeout timeout-val)
    _ (error (.. "unsupported reference type " _))))

(fn async.error! [p err]
  "Set the promise `p` to error state, with `err` set as error cause.
Does nothing if promise was already delivered."
  (let [res (if p.ready
                false
                (do (doto p
                      (tset :val nil)
                      (tset :ready true)
                      (tset :state :error)
                      (tset :error err))
                    true))]
    (when (not scheduler.current-thread)
      (async.run :once))
    res))

(fn shuffle! [t]
  (for [i (length t) 2 -1]
    (let [j (math.random i)
          ti (. t i)]
      (tset t i (. t j))
      (tset t j ti)))
  t)

(fn async.alt [...]
  "Wait for several promises simultaneously, return the value of the
first one ready. Argument order doesn't matter, because the poll order
is shuffled.  For a more non deterministic outcome, call
`math.randomseed` with some seed."
  (let [promises (shuffle! (t/pack ...))
        coroutine? scheduler.current-thread]
    (var the-one nil)
    (while (not the-one)
      (each [_ p (ipairs promises)]
        (when p.ready
          (set the-one p)))
      (when (not the-one)
        (if (and coroutine?)
            (async.park)
            (async.run :once))))
    (the-one:deref)))

(fn file? [f]
  (if (and (= :userdata (type f))
           (string.match (tostring f) "file"))
    true
    false))

;;; IO

(fn async.io.read [file]
  "Read the `file' into a string in a non blocking way.
Returns a promise object to be awaited.  `file' can be a string or a
file handle.  The resource will be closed once operation is complete."
  (let [p (async.promise)
        fh (if (= :string (type file))
               (match (io.open file)
                 fh* fh*
                 (nil msg) (error msg 2))
               (file? file)
               file
               (error (: "bad argument #1 to 'select' (string or FILE* expected, got %s) " :format (type file)) 2))]
    (async.queue
     #(with-open [f fh]
        (var (str res len) (values "" [] 0))
        (while str
          (set str (f:read 1024))
          (when str
            (set len (+ len 1))
            (tset res len str)
            (async.park)))
        (async.deliver p (t/concat res))))
    p))

(fn async.io.write [...]
  "Write the `data' to the `file' in a non blocking way.
Returns a promise object which will be set to `true' once the write is
complete.  Accepts optional `mode`.  By default the `mode` is set to
`\"w\"`."
  (let [(file mode data)
        (match (values (select "#" ...) ...)
          (2 ?file ?data) (values ?file :w ?data)
          (3) ...
          (_) (error (: "wrong amount of arguments (expected 2 or 3, got %s) " :format _) 2))
        fh (if (= :string (type file))
               (match (io.open file mode)
                 fh* fh*
                 (nil msg) (error msg 2))
               (file? file)
               file
               (error (: "bad argument #1 to 'select' (string or FILE* expected, got %s) " :format (type file)) 2))
        p (async.promise)]
    (async.queue
     #(with-open [f fh]
        (each [c (string.gmatch data ".")]
          (f:write c)
          (async.park))
        (async.deliver p true)))
    p))

;;; TCP (experimental)

(local tcp {})
(local closed {})
(local conns {})         ; stores server objects and their connections

(fn make-socket-channel [client close-handler]
  ;; Creates a buffer for a given client socket. The buffer may park
  ;; for more data.
  (->> {:__name "socket-buffer"
        :__fennelview pp
        :__index {:put (fn put [_ val i]
                         (match (socket.select nil [client] 0)
                           (_ [c]) (match (client:send val i)
                                     (nil :timeout j)
                                     (do (async.park)
                                         (put _ val j))
                                     (nil :closed)
                                     (close-handler client)
                                     _ true)
                           _ false))
                  :take (fn take [_ data]
                          (match (socket.select [client] nil 0)
                            [c] (match (client:receive 256)
                                  data* (do (async.park)
                                            (take _ (t/append (or data []) data*)))
                                  (nil :closed data*)
                                  (close-handler client)
                                  (nil :timeout "")
                                  (and data (t/concat data))
                                  (nil :timeout data*)
                                  (do (async.park)
                                      (take _ (t/append (or data []) data*)))
                                  (nil _) (print _))
                            _ (and data (t/concat data))))}}
       (setmetatable {})
       async.chan))

(fn make-server-channel [server]
  ;; Creates a buffer for a given server socket. The buffer is used to
  ;; receive new connections.
  (->> {:__name "socket-server-buffer"
        :__fennelview pp
        :__index {:take #(match (server:accept)
                           client (do (client:settimeout 0)
                                      (tset conns server client true)
                                      client)
                           _ nil)
                  :put #true}}
       (setmetatable {})
       async.chan))

(fn spawn-client-thread [client handler server]
  ;; Spawns a client thread that asynchronously takes from the client
  ;; socket and calls the `handler' when all data was read.
  (async.queue
   (fn loop []
     (match (async.take client 10)
       closed nil
       data (let [res (handler data)]
              (when server.running?
                (async.put client res))
                (loop))
       nil (when server.running?
             (loop))))))

(fn spawn-accept-thread [server handler]
  ;; Spawns a thread that waits for new connections. For each
  ;; connection it spawns a separate thread that calls the `handler'
  ;; on each received value.
  (let [server-chan server.chan
        server-socket server.socket]
    (async.queue
     #(while server.running?
        (match-try (async.take server-chan 100)
          client (make-socket-channel client
                                      (fn [client]
                                        (client:close)
                                        (tset conns server-socket client nil)
                                        closed))
          chan (spawn-client-thread chan handler server))))))

(fn tcp.start-server [handler {: host : port}]
  "Start socket server on a given `host` and `port` with `handler` being
ran for every connection on separate asynchronous threads.

# Examples
Starting a server, connecting a client, sending, and receiving a value:

``` fennel
(let [server (tcp.start-server #(+ 1 (tonumber $)) {})
      port (tcp.getport server)
      client (tcp.connect {:host :localhost :port port})]
  (put client 41)
  (assert-eq 42 (tonumber (take client))))
```"
  (match-try (socket.bind (if (not= host nil) host :localhost)
                          (if (not= port nil) port 0))
    server (server:settimeout 0)
    _ (tset conns server {})
    _ (make-server-channel server)
    server-chan (->> {:__index {:close (fn [self]
                                         (set self.running? false)
                                         (each [client (pairs (. conns server))]
                                           (client:close))
                                         (server:close))}}
                     (setmetatable {:chan server-chan
                                    :socket server
                                    :running? true}))
    chan (spawn-accept-thread chan handler)
    _ (io.stdout:write (string.format "server started at %s:%s\n" (server:getsockname)))
    _ chan
    (catch
        (nil err) (error (.. "unable to start the server: " err)))))

(fn tcp.stop-server [server]
  "Stop the `server` obtained from the `start-server` function.
This also closes all connections, and stops any threads that currently
processing data received from clients."
  (server:close))

(fn tcp.connect [{: host : port}]
  "Connect to the server via `host` and `port`."
  (match-try (socket.connect host port)
    client (client:settimeout 0)
    _ (make-socket-channel client (fn [] (client:close) nil))
    (catch
        (nil err) (error err))))

(fn tcp.gethost [{:socket server}]
  "Get the hostname of the `server`."
  (pick-values 1 (server:getsockname)))

(fn tcp.getport [{:socket server}]
  "Get the port of the `server`."
  (let [(_ port) (server:getsockname)]
    port))

(fn async-repl [data-chan ?opts]
  (var output [])
  (var p nil)
  (var err nil)
  (let [opts (or ?opts {})]
    (fn opts.readChunk [{: stack-size}]
      (when (> stack-size 0)
        (set err "unfinished expression")
        (error nil))
      (when (and (> (length output) 0) p)
        (async.deliver p (.. (table.concat output "\t") "\n")))
      ((fn loop []
         (match (async.take data-chan 100)
           [p* chunk]
           (do
             (set p p*)
             (set output [])
             (and chunk (.. chunk "\n")))
           nil (loop)))))
    (fn opts.onValues [x]
      (table.insert output (table.concat x "\t")))
    (fn opts.onError [_ e]
      (table.insert output (.. "error: " (or e err))))
    (match (pcall require :fennel)
      (true fennel) (async.queue #(fennel.repl opts))
      (_ msg) (error (.. "unable to load fennel: " msg)))))

(fn string-trim [s]
  (: (s:gsub "^%s+" "") :gsub "%s+$" ""))

(fn tcp.start-repl [conn opts]
  "Create a socket REPL with given `conn` and `opts`."
  (let [data-chan (async.chan)]
    (async-repl data-chan opts)
    (tcp.start-server (fn [data]
                        (match (string-trim data)
                          "" "nil\n"
                          data* (let [p (async.promise)]
                                  (async.put data-chan [p data*])
                                  (async.await p))))
                      conn)))

(when socket (set async.tcp tcp))

(setmetatable async {:__call (fn [_ task] (async.queue task))})
