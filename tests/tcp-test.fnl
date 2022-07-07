(require-macros :fennel-test)
(local async (require :async))
(local tcp async.tcp)

(when tcp
  (fn inc-handler [x]
    (-> x tonumber (+ 1)))
  (deftest server-test
    (testing "starting a server on a random port with a simple handler"
      (let [s (tcp.start-server inc-handler {:host "127.0.0.1"})
            port (tcp.get-port s)
            c (tcp.connect {:host "127.0.0.1" :port port})]
        (assert-is (async.try-put c 41))
        (assert-eq 42 (tonumber (async.take c)))
        (tcp.stop-server s)))
    (testing "can't start a server on the same port twice"
      (let [s (tcp.start-server inc-handler {:host "127.0.0.1"})
            port (tcp.get-port s)]
        (assert-not (pcall tcp.start-server inc-handler {:host "127.0.0.1" :port port}))
        (tcp.stop-server s))))
  (deftest puts-test
    (testing "putting to the client doesn't work after server was stopped"
      (let [s (tcp.start-server inc-handler {:host "127.0.0.1"})
            port (tcp.get-port s)
            c (tcp.connect {:host "127.0.0.1" :port port})]
        (tcp.stop-server s)
        (assert-not (async.try-put c 41))))))
