(require-macros :fennel-test)
(local {: queue
        : run
        : park
        : await
        : sleep
        : promise
        : error!
        : alt
        : deliver
        : zip
        : agent
        : send
        : agent-error
        : restart-agent
        : chan
        : put
        : take
        : buffer
        : dropping-buffer
        &as async}
  (require :async))

(use-fixtures :each (fn [t] (t) (run)))

(deftest promise-test
  (testing "promise internal structure"
    (let [p (promise)]
      (assert-eq p {:val nil :ready false})
      (deliver p 1)
      (assert-eq p {:val 1 :ready true})))
  (testing "dereferencing"
    (let [p (promise)]
      (assert-eq (await p 0 :not-set) :not-set)
      (assert-eq (p:deref 0 :not-set) :not-set)
      (deliver p 2)
      (assert-eq (await p 0 :not-set) 2)
      (assert-eq (p:deref 0 :not-set) 2)
      (assert-eq (await p) 2)
      (assert-eq (p:deref) 2)))
  (testing "promise delivered only once"
    (let [p (promise)]
      (deliver p 3)
      (assert-eq (await p) 3)
      (deliver p 4)
      (assert-eq (await p) 3))))

(deftest agent-test
  (testing "agent internal structure"
    (let [a (agent 1)]
      (assert-eq a {:val 1 :state :running :error nil})))
  (testing "dereferencing"
    (let [a (agent 2)]
      (assert-eq (await a) 2)
      (assert-eq (a:deref) 2)))
  (testing "changing agent with send"
    (let [a (agent 3)]
      (assert-eq (await a) 3)
      (send a (fn [val] (+ val 1)))
      (assert-eq (await a) 4)))
  (testing "agent error"
    (let [a (agent 5)
          e {}]
      (assert-eq (await a) 5)
      (send a (fn [val] (error e)))
      (assert-eq (agent-error a) e)
      (assert-eq (match (pcall await a) (false _) _) e)
      (restart-agent a 42)
      (assert-eq (await a) 42))))

(deftest buffer-test
  (testing "buffer internal structure"
    (let [b1 (buffer)
          b2 (buffer 10)
          b3 (dropping-buffer 10)]
      (assert-eq b1 {:size math.huge})
      (assert-eq b2 {:size 10})
      (assert-eq b3 {:size 10})))
  (testing "error handling"
    (assert-not (pcall buffer "10"))
    (assert-not (pcall dropping-buffer))
    (assert-not (pcall dropping-buffer "10"))))

(deftest chan-test
  (testing "channel internal structure"
    (let [c1 (chan)
          c2 (chan 10)
          c3 (chan (buffer))
          c4 (chan (buffer 10))
          c5 (chan (dropping-buffer 10))
          xform #$
          c6 (chan nil xform)
          c7 (chan 10 xform)
          c8 (chan (dropping-buffer 10) xform)]
      (assert-eq c1 {:buffer {:size math.huge} :xform nil})
      (assert-eq c2 {:buffer {:size 10} :xform nil})
      (assert-eq c1 c3)
      (assert-eq c2 c5)
      (assert-eq c6 {:buffer {:size math.huge} : xform})
      (assert-eq c7 {:buffer {:size 10} : xform})
      (assert-eq c7 c8)))
  (testing "put and take"
    (let [c1 (chan)
          c2 (chan 10)]
      (assert-is (put c1 "a"))
      (assert-eq (take c1) "a")
      (assert-is (put c2 "b"))
      (assert-eq (take c2) "b")))
  (testing "put with xform"
    (let [c1 (chan nil #(if (= 0 (% $ 2)) $))]
      (assert-is (put c1 1000))
      (assert-is (put c1 1001))
      (assert-eq (take c1) 1000)
      (assert-eq (take c1 0 :no-val) :no-val)))
  (testing "dropping put"
    (let [c (chan (dropping-buffer 1))]
      (put c "c")
      (assert-eq c {:buffer {1 "c" :size 1}})
      (put c "d")
      (assert-eq c {:buffer {1 "c" :size 1}})
      (assert-eq (take c) "c")))
  (testing "blocking put"
    (let [c (chan 1)]
      (put c "e")
      (assert-eq c {:buffer {1 "e" :size 1}})
      (queue #(put c "f"))
      (assert-eq c {:buffer {1 "e" :size 1}})
      (assert-eq (take c) "e")
      (assert-eq c {:buffer {1 "f" :size 1}})
      (assert-eq (take c) "f")))
  (testing "blocking take"
    (let [c (chan)]
      (queue #(do (sleep 100) (put c 42)))
      (assert-eq (take c 10) nil)
      (assert-eq (take c) 42)))
  (testing "asynchronous take"
    (let [c (chan)]
      (var res nil)
      (queue #(set res (take c)))
      (assert-eq res nil)
      (run :once)
      (put c 42)
      (assert-eq res 42)))
  (testing "take with timeout"
    (let [c (chan 1)]
      (assert-eq :no-value (take c 10 :no-value))
      (put c "g")
      (assert-eq "g" (take c 0 :no-value))))
  (testing "incorrect size type"
    (assert-not (pcall chan "1"))))

(deftest await-test
  (testing "await promise"
    (let [p (promise)]
      (var res nil)
      (queue #(set res (await p)))
      (assert-eq res nil)
      (deliver p 10)
      (assert-eq res 10)))
  (testing "await promise with timeout"
    (let [p (promise)]
      (var res nil)
      (queue #(set res (await p 100 :not-delivered)))
      (async.run)
      (assert-eq res :not-delivered)
      (deliver p 20)
      (assert-eq res :not-delivered)
      (queue #(set res (await p 100 :not-delivered)))
      (assert-eq res 20)))
  (testing "await promise with timeout synchronously"
    (let [p (promise)]
      (var res nil)
      (queue #(do (sleep 100) (deliver p 2000)))
      (assert-eq nil (await p 10))
      (assert-eq 2000 (await p))))
  (testing "await multiple promises"
    (let [p1 (promise)
          p2 (promise)]
      (queue #(deliver p2 (+ 1 (await p1))))
      (queue #(do (park) (deliver p1 30)))
      (assert-eq {1 30 2 31 :n 2} (zip p1 p2)))))

(deftest park-test
  (testing "parking main thread does nothing"
    (assert-eq nil (park)))
  (testing "parking queued task prevents it from running"
    (var res nil)
    (queue #(do (park) (set res 100)))
    (assert-eq res nil)
    (run)
    (assert-eq res 100)))

(deftest sleep-test
  ;; (testing "all tasks sleep"
  ;;   (var res 0)
  ;;   (zip (queue #(do (sleep 100) (set res (+ res 1))))
  ;;        (queue #(do (sleep 100) (set res (+ res 2))))
  ;;        (queue #(do (sleep 100) (set res (+ res 3)))))
  ;;   (assert-eq res 6))
  (let [clock
        (match (pcall require :socket)
          (true socket) socket.gettime
          (false) (match (pcall require :posix)
                    (true posix) #(let [(s ms) (posix.clock_gettime)]
                                    (tonumber (.. s "." ms)))
                    (false) nil))]
    (when (and clock os.clock)
      (testing "cpu time low"
        (let [cpu-start (os.clock)
              test-start (clock)
              _ (await (queue #(sleep 1000)))
              _ (sleep 100)
              cpu-time (- (os.clock) cpu-start)
              test-time (- (clock) test-start)]
          (assert-is (< cpu-time (/ test-time 100))
                     (string.format "non-optimal CPU usage. CPU time: %s, test time: %s" cpu-time test-time))))))
  (testing "all tasks sleep"
    (var res 0)
    (queue #(do (sleep 100) (set res (+ res 2))))
    (queue #(do (park) (park) (set res (+ res 3))))
    (queue #(do (sleep 100) (set res (+ res 4))))
    (run)
    (assert-eq res 9)))

(deftest error-test
  (testing "error in thread"
    (let [e {}]
      (assert-eq e (match (pcall await (queue #(error e))) (false _) _))))
  (testing "error in promise"
    (let [p (promise)
          e {}]
      (error! p e)
      (assert-eq e (match (pcall await p) (false _) _))))
  (testing "error in delivered promise"
    (let [p (promise)
          e {}]
      (deliver p 322)
      (error! p e)
      (assert-eq 322 (match (pcall await p) (true v) v))))
  (testing "unsupported mode"
    (assert-not (pcall run :nope)))
  (testing "unsupported reference"
    (assert-not (pcall await {}))))

(deftest module-callable-test
  (testing "module can be called as function"
    (assert-is (async #nil))))

(deftest alt-test
  (testing "alt returns a random choice"
    (let [res (alt (queue #42) (queue #43))]
      (assert-is (or (= res 42) (= res 43)))))
  (testing "shortest task always wins"
    (let [res (alt (queue #(do (park) (park) (park) 44)) (queue #(do (park) 45)))]
      (assert-eq 45 res)))
  (testing "alt works asynchronously"
    (let [p1 (promise)
          p2 (promise)]
      (var res nil)
      (queue #(set res (alt p1 p2)))
      (assert-eq res nil)
      (deliver p1 46)
      (assert-eq 46 res))))
