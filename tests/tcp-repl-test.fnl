(require-macros :fennel-test)
(local async (require :async))
(local tcp async.tcp)

(local lprint _G.print)

(fn take-all [c]
  (let [timeout (setmetatable {} {:__name "timeout"})]
    (async.sleep 100)
    ((fn loop [res]
       (match res
         timeout (tostring res)
         _ (match (async.take c 100 timeout)
             timeout res
             data (loop (.. res data)))))
     (async.take c 10000 timeout))))

(when tcp
  (deftest repl-test
    (testing "running a tcp repl"
      (let [s (tcp.start-repl {:host "localhost"})
            port (tcp.get-port s)
            c (tcp.connect {:host "localhost" :port port})]
        (assert-is (async.try-put c "\n"))
        (assert-eq "nil\n" (take-all c))
        (assert-is (async.try-put c "(+ 1 2 3)"))
        (assert-eq 6 (tonumber (take-all c)))
        (tcp.stop-server s))))
  (deftest error-test
    (testing "error in repl"
      (let [s (tcp.start-repl {:host "localhost"})
            port (tcp.get-port s)
            c (tcp.connect {:host "localhost" :port port})]
        (assert-is (async.try-put c "(+ 1 2"))
        (assert-is (string.match (take-all c) "Parse error"))
        (tcp.stop-server s))
      (let [s (tcp.start-repl {:host "localhost"})
            port (tcp.get-port s)
            c (tcp.connect {:host "localhost" :port port})]
        (assert-is (async.try-put c "x"))
        (assert-is (string.match (take-all c) "Compile error"))
        (tcp.stop-server s))))
  (deftest output-test
    (testing "printing over the repl"
      (let [s (tcp.start-repl {:host "localhost"})
            port (tcp.get-port s)
            c (tcp.connect {:host "localhost" :port port})]
        (assert-is (async.try-put c "(print 10)"))
        (assert-eq (take-all c) "10\nnil\n")
        (assert-is (async.try-put c "(io.write 11)"))
        (assert-eq (take-all c) "11nil\n")
        (assert-is (async.try-put c "(io.stdout:write 12)"))
        (assert-eq (take-all c) "12nil\n")
        (assert-is (async.try-put c "(io.stderr:write 13)"))
        (assert-eq (take-all c) "13nil\n")
        (tcp.stop-server s))))
  (deftest input-test
    (testing "reading over the repl"
      (fn multi-put [c lines]
        (each [_ line (ipairs lines)]
          (assert-is (async.try-put c line))
          (async.sleep 100)))
      (let [s (tcp.start-repl {:host "localhost"})
            port (tcp.get-port s)
            c (tcp.connect {:host "localhost" :port port})]
        (multi-put c ["(io.read)" "test test\n"])
        (assert-eq (take-all c) "\"test test\"\n")
        (multi-put c ["(io.read :l)" "test test\n"])
        (assert-eq (take-all c) "\"test test\"\n")
        (multi-put c ["(io.read :L)" "test test\n"])
        (assert-eq (take-all c) "\"test test\n\"\n")
        (multi-put c ["(io.read :a)" "test test\ntest test\n"])
        (assert-eq (take-all c) "\"test test\ntest test\n\"\n")
        (multi-put c ["(+ 41 (io.read :n))" "1\n"])
        (assert-eq 42 (tonumber (take-all c)))
        (assert-is (async.try-put c "(local x 10)"))
        (assert-eq "nil\n" (take-all c))
        (multi-put c ["(io.read 3)" "foo x\n"])
        (assert-eq (take-all c) "\"foo\"\n10\n")
        (tcp.stop-server s)))))
