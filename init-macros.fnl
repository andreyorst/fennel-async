(local async
  ;; Constructing relative paths for comp-time require call splicing
  (if (or (= nil ...) (= ... :init-macros)) :init ...))


(fn a/for [bindings ...]
  "Asyncronous `for` loop.

Accepts `park-form` before `bindings` to call before the body of the
loop on each iteration. If `park-form` is a list, evaluates it as is,
if it's a symbol calls it as a function.

# Examples

Spawn a `for` loop that parks itself on each iteration and puts into
an unbounded channel.  After spawning the channel is still empty, but
upon taking from it the loop advances, pushing values onto the chan.

``` fennel
(let [c (chan)]
  (queue #(a/for [i 1 4] (put c i)))
  (assert-eq 0 (length c.buffer))
  (assert-eq [1 2 3 4] (take-all c 100)))
```"
  `(let [{:park park#} (require ,async)]
     (for ,bindings
       (park#)
       (do ,...))))

(fn a/each [bindings ...]
  "Asyncronous `each` loop.

Accepts `park-form` before `bindings` to call before the body of the
loop on each iteration. If `park-form` is a list, evaluates it as is,
if it's a symbol calls it as a function.

# Examples

Spawn an `each` loop that parks itself on each iteration and puts into
an unbounded channel.  After spawning the channel is still empty, but
upon taking from it the loop advances, pushing values onto the chan.

``` fennel
(let [c (chan)]
  (queue #(a/each [_ v (ipairs [1 2 3 4])] (put c v)))
  (assert-eq 0 (length c.buffer))
  (assert-eq [1 2 3 4] (take-all c 100)))
```"
  `(let [{:park park#} (require ,async)]
     (each ,bindings
       (park#)
       (do ,...))))

(fn a/while [test ...]
  "Asyncronous `while` loop.

Accepts `park-form` before `test` to call before the body of the
loop on each iteration. If `park-form` is a list, evaluates it as is,
if it's a symbol calls it as a function."
  `(let [{:park park#} (require ,async)]
     (while ,test
       (park#)
       (do ,...))))

(fn a/collect [bindings ...]
  "Asyncronous `collect` table comprehension.

Accepts `park-form` before `bindings` to call before the body of the
loop on each iteration. If `park-form` is a list, evaluates it as is,
if it's a symbol calls it as a function.  Returns a value when
finished.

# Examples

``` fennel
(let [p (promise)]
  (queue #(->> (a/collect [k v (pairs {:a 1 :b 2})]
                 (values (string.upper k) (+ v 1)))
               (deliver p)))
  (assert-not p.ready)                ; promise is not yet delivered
  (run :once)                         ; run each queued task once
  (assert-not p.ready)                ; promise is still not delivered
  (assert-eq (await p) {:A 2 :B 3}))  ; awaiting realizes the loop
```"
  `(let [{:park park#} (require ,async)]
     (collect ,bindings
       (do (park#)
           (do ,...)))))

(fn a/icollect [bindings ...]
  "Asyncronous `icollect` table comprehension.

Accepts `park-form` before `bindings` to call before the body of the
loop on each iteration. If `park-form` is a list, evaluates it as is,
if it's a symbol calls it as a function.  Returns a value when
finished.

# Examples

``` fennel
(let [p (promise)]
  (queue #(->> (a/icollect [_ v (ipairs [1 2 3 4])]
                 (+ v 1))
               (deliver p)))
  (assert-not p.ready)                ; promise is not yet delivered
  (run :once)                         ; run each queued task once
  (assert-not p.ready)                ; promise is still not delivered
  (assert-eq (await p) [2 3 4 5]))    ; awaiting realizes the loop
```"
  `(let [{:park park#} (require ,async)]
     (icollect ,bindings
       (do (park#)
           (do ,...)))))

(comment
 (fn a/fcollect [bindings ...]
   "Asyncronous `fcollect` table comprehension.

Accepts `park-form` before `bindings` to call before the body of the
loop on each iteration. If `park-form` is a list, evaluates it as is,
if it's a symbol calls it as a function.  Returns a value when
finished.

# Examples

``` fennel
(let [p (promise)]
  (queue #(->> (a/fcollect [v 1 4]
                 (+ v 1))
               (deliver p)))
  (assert-not p.ready)                ; promise is not yet delivered
  (run :once)                         ; run each queued task once
  (assert-not p.ready)                ; promise is still not delivered
  (assert-eq (await p) [2 3 4 5]))    ; awaiting realizes the loop
```"
   `(let [{:park park#} (require ,async)]
      (fcollect ,bindings
        (do (park#)
            (do ,...))))))

(fn a/accumulate [bindings ...]
  "Asyncronous `accumulate` variant.

Accepts `park-form` before `bindings` to call before the body of the
loop on each iteration. If `park-form` is a list, evaluates it as is,
if it's a symbol calls it as a function.  Returns a value when
finished.

# Examples

``` fennel
(let [p (promise)]
  (queue #(->> (a/accumulate [sum 0 _ v (ipairs [1 2 3 4])]
                 (+ sum v))
               (deliver p)))
  (assert-not p.ready)                ; promise is not yet delivered
  (run :once)                         ; run each queued task once
  (assert-not p.ready)                ; promise is still not delivered
  (assert-eq (await p) 10))           ; awaiting realizes the loop
```"
  `(let [{:park park#} (require ,async)]
     (accumulate ,bindings
       (do (park#)
           (do ,...)))))

{: a/accumulate
 ;; : a/fcollect ; TODO: not yet released
 : a/icollect
 : a/collect
 : a/while
 : a/each
 : a/for}
