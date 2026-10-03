;;;; lisp-polycall real-core tests (SBCL). Run through tests/run-real-core.sh,
;;;; which starts a `polycall start` runtime and exports POLYCALL_* test
;;;; variables. A test whose prerequisites are missing is SKIPPED, never
;;;; counted as passed. Prints PASS/FAIL/SKIP per test; exit 1 on any FAIL.

(defpackage #:lisp-polycall/tests
  (:use #:cl #:lisp-polycall)
  (:export #:run-tests #:run-tests-and-exit))

(in-package #:lisp-polycall/tests)

;;; ---- harness -------------------------------------------------------------------

(defvar *tests* '())
(define-condition test-skipped (error) ((reason :initarg :reason :reader skip-reason)))

(defmacro deftest (name &body body)
  `(setf *tests* (append (remove ',name *tests* :key #'car) (list (cons ',name (lambda () ,@body))))))

(defun skip (fmt &rest args) (error 'test-skipped :reason (apply #'format nil fmt args)))

(defmacro is (form &optional description)
  `(unless ,form (error "assertion failed~@[ (~A)~]: ~S" ,description ',form)))

(defmacro is-equal (expected form &optional description)
  (let ((e (gensym)) (v (gensym)))
    `(let ((,e ,expected) (,v ,form))
       (unless (equalp ,e ,v)
         (error "expected ~S, got ~S from ~S~@[ (~A)~]" ,e ,v ',form ,description)))))

(defmacro status-of (&body body)
  "The POLYCALL status BODY signalled, or :OK."
  `(handler-case (progn ,@body :ok)
     (polycall-error (c) (polycall-error-status c))))

(defmacro condition-of (&body body)
  `(handler-case (progn ,@body nil)
     (polycall-error (c) c)))

(defun env (name)
  (let ((v (uiop:getenv name)))
    (if (and v (plusp (length v))) v (skip "~A is not set (run tests/run-real-core.sh)" name))))

(defun run-tests ()
  (let ((pass 0) (fail 0) (skipped 0))
    (dolist (test *tests*)
      (let ((name (string-downcase (symbol-name (car test)))))
        (handler-case
            (progn (funcall (cdr test)) (incf pass) (format t "PASS  ~A~%" name))
          (test-skipped (c) (incf skipped) (format t "SKIP  ~A: ~A~%" name (skip-reason c)))
          (error (c) (incf fail) (format t "FAIL  ~A: ~A~%" name c)))
        (finish-output)))
    (format t "~&lisp-polycall: ~D passed, ~D failed, ~D skipped~%" pass fail skipped)
    (values pass fail skipped)))

(defun run-tests-and-exit ()
  (multiple-value-bind (pass fail) (run-tests)
    (declare (ignore pass))
    (uiop:quit (if (zerop fail) 0 1))))

;;; ---- helpers ---------------------------------------------------------------------

(defun tmp (name) (concatenate 'string (env "POLYCALL_TEST_TMP") "/" name))
(defun write-text (name text)
  (let ((p (tmp name))) (with-open-file (s p :direction :output :if-exists :supersede) (write-string text s)) p))
(defun bytes (&rest parts)
  (let ((out (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0)))
    (dolist (p parts (coerce out '(simple-array (unsigned-byte 8) (*))))
      (loop for b across (if (stringp p) (babel:string-to-octets p :encoding :utf-8) p)
            do (vector-push-extend b out)))))
(defun all-bytes () (coerce (loop for i below 256 collect i) '(vector (unsigned-byte 8))))
(defun utf8 (s) (babel:string-to-octets s :encoding :utf-8))
(defun take (peer &optional (timeout 3000)) (peer-recv peer :timeout-ms timeout))
(defun msg= (m sender id payload)
  (and (string= sender (message-sender m)) (string= id (message-id m))
       (equalp (bytes payload) (message-payload m))))

(defun base64 (octets)
  (let ((alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"))
    (with-output-to-string (out)
      (loop for i from 0 below (length octets) by 3
            for n = (- (length octets) i)
            for b0 = (aref octets i)
            for b1 = (if (> n 1) (aref octets (+ i 1)) 0)
            for b2 = (if (> n 2) (aref octets (+ i 2)) 0)
            for w = (logior (ash b0 16) (ash b1 8) b2)
            do (write-char (char alphabet (ldb (byte 6 18) w)) out)
               (write-char (char alphabet (ldb (byte 6 12) w)) out)
               (write-char (if (> n 1) (char alphabet (ldb (byte 6 6) w)) #\=) out)
               (write-char (if (> n 2) (char alphabet (ldb (byte 6 0) w)) #\=) out)))))

(defun json-field (json key)
  (let* ((needle (format nil "\"~A\":\"" key))
         (start (search needle json)))
    (when start
      (let* ((s (+ start (length needle))) (e (position #\" json :start s)))
        (subseq json s e)))))

(defun cli (&rest args)
  "Run the polycall CLI; returns (values stdout exit-code)."
  (multiple-value-bind (out err code)
      (uiop:run-program (cons (env "POLYCALL_CLI") args) :output :string :error-output :string
                                                           :ignore-error-status t)
    (declare (ignore err))
    (values out code)))

(defun child-sbcl (env-assignments form)
  "Evaluate FORM (a string) in a fresh SBCL with ENV-ASSIGNMENTS; (values output exit-code)."
  (multiple-value-bind (out err code)
      (uiop:run-program (append (list "env") env-assignments
                                (list "sbcl" "--noinform" "--non-interactive"
                                      "--eval" "(require :asdf)"
                                      "--eval" (format nil "(asdf:load-asd ~S)" (env "LISP_POLYCALL_ASD"))
                                      "--eval" "(asdf:load-system \"lisp-polycall\")"
                                      "--eval" form))
                        :output :string :error-output :string :ignore-error-status t)
    (values (concatenate 'string out err) code)))

(defmacro with-peers ((&rest specs) &body body)
  "Each spec is (var node-id &rest open-args); all are closed afterwards."
  (if (null specs)
      `(progn ,@body)
      `(with-peer ,(first specs) (with-peers ,(rest specs) ,@body))))

;;; ---- library -------------------------------------------------------------------------

(deftest version-and-abi
  (is-equal 1 (abi-version))
  (let ((v (polycall-version)))
    (is (and (>= (length v) 5) (string= "1." (subseq v 0 2))) v)
    (is (>= (parse-integer v :start 2 :junk-allowed t) 1)))
  (is (string= (namestring (truename (env "POLYCALL_LIBRARY"))) (namestring (truename (library-path))))
      "POLYCALL_LIBRARY is honoured first"))

(deftest strerror-names-every-status
  (let ((names (loop for s from 0 downto -18
                     collect (subseq (strerror s) 0 (position #\: (strerror s))))))
    (is-equal "POLYCALL_OK" (first names))
    (is-equal "POLYCALL_E_TIMEOUT" (nth 4 names))
    (is-equal "POLYCALL_E_INTERNAL" (nth 18 names))
    (is-equal 19 (length (remove-duplicates names :test #'string=)))
    (is (search "POLYCALL_E_UNKNOWN" (strerror -999)))))

(deftest errors-carry-status-name-and-detail
  (let ((c (condition-of (peer-endpoint (make-peer :handle 987654)))))
    (is-equal +e-invalid-handle+ (polycall-error-status c))
    (is-equal "POLYCALL_E_INVALID_HANDLE" (polycall-error-name c))
    (is (search "handle" (polycall-error-detail c)))
    (is (search "POLYCALL_E_INVALID_HANDLE" (princ-to-string c))))
  (is-equal 0 (run-config))
  (is-equal "" (last-error)))

(deftest last-error-is-per-thread
  (is-equal +e-invalid-handle+ (status-of (peer-node-id (make-peer :handle 424242))))
  (is-equal "" (sb-thread:join-thread (sb-thread:make-thread #'last-error)))
  (is (plusp (length (last-error)))))

(deftest missing-library-is-a-clear-error
  (multiple-value-bind (out code)
      (child-sbcl (list "POLYCALL_LIBRARY=/nonexistent/libpolycall.so.1")
                  "(handler-case (progn (lisp-polycall:abi-version) (uiop:quit 0)) (lisp-polycall:polycall-library-error (c) (format t \"~A~%\" c) (uiop:quit (- (lisp-polycall:polycall-error-status c)))))")
    (is-equal 7 code)
    (is (search "/nonexistent/libpolycall.so.1" out) out)))

(deftest old-core-without-abi-v1-symbols-is-rejected
  (multiple-value-bind (out code)
      (child-sbcl (list (format nil "POLYCALL_LIBRARY=~A" (env "POLYCALL_TEST_FAKE_OLD")))
                  "(handler-case (progn (lisp-polycall:abi-version) (uiop:quit 0)) (lisp-polycall:polycall-library-error (c) (format t \"~A~%\" c) (uiop:quit (- (lisp-polycall:polycall-error-status c)))))")
    (is-equal 15 code)
    (is (search "missing symbol" out) out)
    (is (search "polycall_ffi_abi_version" out) out)))

(deftest abi-mismatch-is-rejected
  (multiple-value-bind (out code)
      (child-sbcl (list (format nil "POLYCALL_LIBRARY=~A" (env "POLYCALL_TEST_FAKE_ABI2")))
                  "(handler-case (progn (lisp-polycall:abi-version) (uiop:quit 0)) (lisp-polycall:polycall-library-error (c) (format t \"~A~%\" c) (uiop:quit (- (lisp-polycall:polycall-error-status c)))))")
    (is-equal 15 code)
    (is (search "reports binding ABI 2" out) out)))

;;; ---- configuration ------------------------------------------------------------------------

(deftest shipped-rc-files-validate-strictly
  (let ((repo (env "LISP_POLYCALL_REPO")))
    (is-equal 0 (run-config (concatenate 'string repo "/lisp-polycallrc")))
    (is-equal 0 (run-config (concatenate 'string repo "/examples/lisp-polycallrc") t))
    (is-equal nil (run-config-or-error (concatenate 'string repo "/lisp-polycallrc")))
    (is (search "\"layer\"" (describe-config (concatenate 'string repo "/lisp-polycallrc"))))))

(deftest missing-and-empty-paths
  (is-equal +e-not-found+ (run-config (tmp "missing-polycallrc")))
  (is-equal +e-invalid-argument+ (run-config ""))
  (let ((c (condition-of (run-config-or-error "/nonexistent/lisp-polycallrc"))))
    (is-equal +e-not-found+ (polycall-error-status c))
    (is-equal "/nonexistent/lisp-polycallrc" (polycall-error-config-path c))))

(deftest invalid-value-names-the-key
  (let ((p (write-text "bad-polycallrc" (format nil "max_connections=lots~%"))))
    (is-equal +e-config+ (run-config p nil))
    (is (search "max_connections" (last-error)))
    (is (search "max_connections" (polycall-error-detail (condition-of (run-config-or-error p)))))))

(deftest unknown-key-warning-unless-strict
  (let ((p (write-text "unknown-polycallrc" (format nil "log_level=info~%mystery_key=1~%"))))
    (is-equal 0 (run-config p nil))
    (is-equal +e-config+ (run-config p t))
    (is-equal +e-config+ (run-config p))))

(deftest tls-refused-not-faked-when-strict
  (let ((p (write-text "tls-polycallrc" (format nil "tls_enabled=true~%cert_file=/x/c.pem~%key_file=/x/k.pem~%"))))
    (is-equal 0 (run-config p nil))
    (is-equal +e-unsupported+ (run-config p t))
    (is (search "tls" (string-downcase (last-error))))))

;;; ---- polycall_call ---------------------------------------------------------------------------

(deftest call-success
  (let ((ep (env "POLYCALL_TEST_RPC_ENDPOINT")))
    (is-equal "{\"item_id\":\"widget-a\",\"quantity\":42,\"in_stock\":true}"
              (polycall-call ep "inventory" "get" :input "{\"item_id\":\"widget-a\"}" :timeout-ms 2000))
    (is-equal "{\"echo\":null}" (polycall-call ep "debug" "echo" :timeout-ms 2000))
    (let ((in (format nil "{\"s\":\"h~Cllo ~C\"}" (code-char #xe9) (code-char #x1f30d))))
      (is-equal (format nil "{\"echo\":~A}" in) (polycall-call ep "debug" "echo" :input in :timeout-ms 2000)))))

(deftest call-unknown-operation
  (is-equal +e-not-found+ (status-of (polycall-call (env "POLYCALL_TEST_RPC_ENDPOINT") "inventory" "teleport" :input "{}"))))

(deftest call-remote-error-carries-the-error-object
  (let ((c (condition-of (polycall-call (env "POLYCALL_TEST_RPC_ENDPOINT") "inventory" "get"
                                        :input "{\"item_id\":\"nope\"}" :timeout-ms 2000))))
    (is-equal +e-remote+ (polycall-error-status c))
    (is (search "item.unknown" (polycall-error-output c)))))

(deftest call-deadline-exceeded
  (let ((t0 (get-internal-real-time)))
    (is-equal +e-timeout+ (status-of (polycall-call (env "POLYCALL_TEST_RPC_ENDPOINT") "debug" "sleep"
                                                    :input "{\"ms\":2000}" :timeout-ms 150)))
    (is (< (/ (- (get-internal-real-time) t0) internal-time-units-per-second) 1.9))))

(deftest call-invalid-input
  (let ((ep (env "POLYCALL_TEST_RPC_ENDPOINT")))
    (is-equal +e-invalid-argument+ (status-of (polycall-call ep "debug" "echo" :input "{not json")))
    (is-equal +e-invalid-argument+ (status-of (polycall-call ep "debug" "echo" :input "{}" :timeout-ms 0)))
    (is-equal +e-invalid-argument+ (status-of (polycall-call "no-port" "debug" "echo")))))

(deftest call-no-runtime
  (is-equal +e-transport+ (status-of (polycall-call "127.0.0.1:1" "inventory" "get" :input "{}" :timeout-ms 1000))))

;;; ---- peers ----------------------------------------------------------------------------------------

(deftest peer-identity-endpoint-and-send-only-node
  (with-peers ((a "alpha") (s "sender-only" :bind nil))
    (is (plusp (peer-handle a)))
    (is-equal "alpha" (peer-node-id a))
    (let ((ep (peer-endpoint a)))
      (is (and (string= "127.0.0.1:" (subseq ep 0 10)) (plusp (parse-integer ep :start 10)))))
    (is-equal "" (peer-endpoint s))
    (is (/= (peer-handle a) (peer-handle s)))
    (is (search "\"node_id\":\"alpha\"" (peer-health a)))))

(deftest peer-payloads-both-directions
  (with-peers ((a "alpha") (b "beta"))
    (peer-register a "beta" (peer-endpoint b))
    (peer-register b "alpha" (peer-endpoint a))
    (peer-send a "beta" "hello beta" :message-id "a2b-1")
    (is (msg= (take b) "alpha" "a2b-1" "hello beta"))
    (peer-send b "alpha" "hello alpha" :message-id "b2a-1")
    (is (msg= (take a) "beta" "b2a-1" "hello alpha"))
    (is (peer-ping a "beta"))
    (is (peer-ping b (peer-endpoint a)))))

(deftest peer-payload-matrix
  (with-peers ((a "alpha") (b "beta"))
    (peer-register a "beta" (peer-endpoint b))
    (peer-send a "beta" (bytes) :message-id "empty-1")
    (is (msg= (take b) "alpha" "empty-1" (bytes)))
    (let ((u (format nil "h~Cllo ~C ~C~C ~C" (code-char #xe9) (code-char #x2014) (code-char #x4e16)
                     (code-char #x754c) (code-char #x1f30d))))
      (peer-send a "beta" u :message-id "utf8-1")
      (let ((m (take b)))
        (is (msg= m "alpha" "utf8-1" u))
        (is-equal 22 (length (message-payload m)))
        (is-equal u (babel:octets-to-string (message-payload m) :encoding :utf-8))))
    (let ((bin (bytes (all-bytes) (coerce #(0 0 116 97 105 108 0) '(vector (unsigned-byte 8))))))
      (peer-send a "beta" bin :message-id "binary-1")
      (is (msg= (take b) "alpha" "binary-1" bin)))
    (let ((max (make-array (ash 1 20) :element-type '(unsigned-byte 8))))
      (dotimes (i (length max)) (setf (aref max i) (mod (* i 7) 256)))
      (peer-send a "beta" max :message-id "max-1" :timeout-ms 10000)
      (let ((m (take b 5000)))
        (is-equal "max-1" (message-id m))
        (is (equalp max (message-payload m)) "exactly 1 MiB identical"))
      (let ((over (make-array (1+ (ash 1 20)) :element-type '(unsigned-byte 8) :initial-element 1)))
        (is-equal +e-too-large+ (status-of (peer-send a "beta" over :message-id "over-1")))))
    (is-equal +e-timeout+ (status-of (peer-recv b :timeout-ms 200)))))

(deftest peer-registry-belongs-to-its-node-only
  (with-peers ((a "alpha") (b "beta"))
    (is-equal '() (peer-list a))
    (peer-register a "beta" (peer-endpoint b))
    (is-equal (list (cons "beta" (peer-endpoint b))) (peer-list a))
    (is-equal '() (peer-list b))
    (is-equal "{}" (peer-list-json b))
    (peer-send a "beta" "x" :message-id "own-1")
    (is (msg= (take b) "alpha" "own-1" "x"))
    (is-equal '() (peer-list b) "receiving never registers the sender")
    (is-equal +e-not-found+ (status-of (peer-send b "alpha" "x")))
    (peer-unregister a "beta")
    (is-equal '() (peer-list a))
    (is-equal +e-not-found+ (status-of (peer-unregister a "beta")))
    (is-equal +e-invalid-argument+ (status-of (peer-register a "bad id!" (peer-endpoint b))))))

(deftest peer-duplicate-message-id-delivered-once
  (with-peers ((a "alpha") (b "beta"))
    (peer-register a "beta" (peer-endpoint b))
    (peer-send a "beta" "once" :message-id "dup-1")
    (peer-send a "beta" "once" :message-id "dup-1")
    (is (msg= (take b) "alpha" "dup-1" "once"))
    (is-equal +e-timeout+ (status-of (peer-recv b :timeout-ms 300)))
    (is (search "\"duplicates\":1" (peer-health b)))))

(deftest peer-auth-failure-rejected-nothing-queued
  (let ((tok (env "POLYCALL_DEV_TOKEN")))
    (with-peers ((b "beta" :token tok) (c "carol" :bind nil) (m "mallory" :bind nil :token "not-the-token")
                 (g "alpha" :bind nil :token tok))
      (is-equal +e-auth+ (status-of (peer-send c (peer-endpoint b) "x" :message-id "auth-1")))
      (is-equal +e-auth+ (status-of (peer-send m (peer-endpoint b) "x" :message-id "auth-2")))
      (is-equal +e-timeout+ (status-of (peer-recv b :timeout-ms 200)))
      (peer-send g (peer-endpoint b) "ok" :message-id "auth-3")
      (is (msg= (take b) "alpha" "auth-3" "ok")))))

(deftest peer-dead-peer-is-transport-error
  (with-peers ((a "alpha"))
    (let* ((d (peer-open "doomed")) (ep (peer-endpoint d)))
      (peer-close d)
      (peer-register a "doomed" ep)
      (is-equal +e-transport+ (status-of (peer-send a "doomed" "into the void" :message-id "dead-1" :timeout-ms 2000)))
      (is-equal +e-transport+ (status-of (peer-ping a ep :timeout-ms 1000))))))

(deftest peer-receive-timeout-and-poll
  (with-peers ((b "beta"))
    (let ((t0 (get-internal-real-time)))
      (is-equal +e-timeout+ (status-of (peer-recv b :timeout-ms 150)))
      (let ((dt (/ (- (get-internal-real-time) t0) internal-time-units-per-second)))
        (is (and (>= dt 1/10) (< dt 3)))))
    (is-equal +e-timeout+ (status-of (peer-recv b :timeout-ms 0)))))

(deftest peer-too-small-buffer-leaves-message-queued
  (with-peers ((a "alpha") (b "beta"))
    (peer-send a (peer-endpoint b) "0123456789" :message-id "size-1")
    (let ((c (condition-of (peer-recv b :timeout-ms 2000 :capacity 4))))
      (is-equal +e-too-large+ (polycall-error-status c))
      (is-equal 10 (polycall-error-output c)))
    (is (msg= (take b) "alpha" "size-1" "0123456789"))))

(defun blocked-recv-thread (peer)
  (sb-thread:make-thread (lambda () (handler-case (peer-recv peer :timeout-ms :infinite)
                                      (polycall-error (c) c)))))

(deftest peer-cancel-wakes-a-blocked-receive
  (with-peers ((b "beta"))
    (let ((th (blocked-recv-thread b)))
      (sleep 0.3)
      (is (sb-thread:thread-alive-p th) "recv is blocked in the core")
      (peer-cancel b)
      (let ((r (sb-thread:join-thread th :default :timeout :timeout 5)))
        (is (typep r 'polycall-error) r)
        (is-equal +e-cancelled+ (polycall-error-status r))))
    (is-equal +e-timeout+ (status-of (peer-recv b :timeout-ms 100)) "later calls wait normally")))

(deftest peer-close-wakes-every-blocked-receive
  (let* ((b (peer-open "beta"))
         (threads (loop repeat 3 collect (blocked-recv-thread b))))
    (sleep 0.3)
    (is (every #'sb-thread:thread-alive-p threads))
    (peer-close b)
    (dolist (th threads)
      (let ((r (sb-thread:join-thread th :default :timeout :timeout 5)))
        (is (typep r 'polycall-error) r)
        (is-equal +e-closed+ (polycall-error-status r))))))

(deftest peer-double-close-calls-after-close-invalid-handles
  (let* ((p (peer-open "closing")) (old (peer-handle p)))
    (peer-close p)
    (is-equal +e-invalid-handle+ (status-of (peer-close p)))
    (dolist (f (list (lambda () (peer-endpoint p)) (lambda () (peer-node-id p))
                     (lambda () (peer-send p "127.0.0.1:1" "x")) (lambda () (peer-recv p :timeout-ms 0))
                     (lambda () (peer-cancel p)) (lambda () (peer-list p)) (lambda () (peer-health p))
                     (lambda () (peer-register p "x" "127.0.0.1:1")) (lambda () (peer-unregister p "x"))
                     (lambda () (peer-ping p "127.0.0.1:1"))))
      (is-equal +e-invalid-handle+ (status-of (funcall f))))
    (dolist (bogus '(0 -1 999999 2147483647))
      (is-equal +e-invalid-handle+ (status-of (peer-ping (make-peer :handle bogus) "127.0.0.1:1"))))
    (with-peers ((n "closing"))
      (is (/= old (peer-handle n)) "a stale handle is never reused")
      (is-equal +e-invalid-handle+ (status-of (peer-endpoint (make-peer :handle old)))))))

(deftest peer-invalid-identifiers
  (is-equal +e-invalid-argument+ (status-of (peer-open "bad id!")))
  (is-equal +e-invalid-argument+ (status-of (peer-open (make-string 64 :initial-element #\x))))
  (is-equal +e-config+ (status-of (peer-open "public" :bind "0.0.0.0:0")))
  (with-peers ((a "alpha"))
    (is-equal +e-invalid-argument+ (status-of (peer-send a (peer-endpoint a) "x" :message-id "bad id!")))))

(defun deliver (peer target id payload busy)
  (loop (handler-case (return (peer-send peer target payload :message-id id))
          (polycall-error (c)
            (unless (= (polycall-error-status c) +e-busy+) (error c))
            (sb-ext:atomic-incf (car busy))
            (sleep 0.01)))))

(deftest peer-concurrent-senders-shared-and-separate-handles
  (with-peers ((b "beta") (shared "shared" :bind nil))
    (let* ((ep (peer-endpoint b)) (per 40) (busy (list 0))
           (threads
             (append
              (loop for k below 4
                    collect (let ((k k))
                              (sb-thread:make-thread
                               (lambda () (dotimes (i per)
                                            (deliver shared ep (format nil "shared-~D-~D" k i)
                                                     (format nil "s~D:~D" k i) busy))))))
              (loop for k from 4 below 8
                    collect (let ((k k))
                              (sb-thread:make-thread
                               (lambda () (with-peer (own (format nil "own~D" k) :bind nil)
                                            (dotimes (i per)
                                              (deliver own ep (format nil "own~D-~D" k i)
                                                       (format nil "o~D:~D" k i) busy)))))))))
           (seen (make-hash-table :test #'equal)))
      (dotimes (i (* 8 per))
        (let ((m (take b 10000)))
          (setf (gethash (message-id m) seen)
                (cons (message-sender m) (babel:octets-to-string (message-payload m))))))
      (dolist (th threads) (sb-thread:join-thread th))
      (is-equal (* 8 per) (hash-table-count seen))
      (is-equal '("shared" . "s3:39") (gethash "shared-3-39" seen))
      (is-equal '("own6" . "o6:7") (gethash "own6-7" seen))
      (is-equal +e-timeout+ (status-of (peer-recv b :timeout-ms 200)))
      (when (plusp (car busy))
        (format t "      [backpressure] ~D E_BUSY answers retried with the same id~%" (car busy))))))

;;; ---- interop with the C CLI peer ----------------------------------------------------------------------

(defun start-cli-node (id)
  (let ((file (tmp (format nil "~A.lisp.ep" id))))
    (when (probe-file file) (delete-file file))
    (let ((proc (uiop:launch-program (list (env "POLYCALL_CLI") "peer" "serve" "--node-id" id
                                           "--endpoint" "127.0.0.1:0" "--endpoint-file" file)
                                     :output nil :error-output nil)))
      (loop repeat 100
            do (when (and (probe-file file) (with-open-file (s file) (plusp (file-length s))))
                 (return-from start-cli-node
                   (values proc (string-trim '(#\Space #\Newline #\Return) (uiop:read-file-string file)))))
               (sleep 0.1))
      (uiop:terminate-process proc)
      (error "polycall peer serve did not start"))))

(deftest interop-lisp-peer-and-cli-peer-exchange-both-ways
  (multiple-value-bind (proc cep) (start-cli-node "cnode")
    (unwind-protect
         (with-peers ((h "lisp-node" :token (env "POLYCALL_DEV_TOKEN")))
           (peer-register h "cnode" cep)
           (is (peer-ping h "cnode" :timeout-ms 2000))
           (let ((payload (bytes (coerce #(108 105 115 112 0 116 111 255 67 32) '(vector (unsigned-byte 8))) (all-bytes))))
             (peer-send h "cnode" payload :message-id "lisp-to-c-1")
             (multiple-value-bind (out code) (cli "peer" "recv" "--to" cep "-t" "3000")
               (is-equal 0 code)
               (is-equal "lisp-node" (json-field out "from"))
               (is-equal "lisp-to-c-1" (json-field out "id"))
               (is-equal (base64 payload) (json-field out "payload_b64"))))
           (let* ((back (bytes "C" (coerce #(0) '(vector (unsigned-byte 8))) "to Lisp " (reverse (all-bytes))))
                  (file (tmp "c-to-lisp.bin")))
             (with-open-file (s file :direction :output :element-type '(unsigned-byte 8) :if-exists :supersede)
               (write-sequence back s))
             (is-equal 0 (nth-value 1 (cli "peer" "send" "--from" "cnode" "--to" (peer-endpoint h)
                                           "--id" "c-to-lisp-1" "--payload-file" file)))
             (is (msg= (take h) "cnode" "c-to-lisp-1" back)))
           (peer-send h "cnode" "again" :message-id "lisp-dup-1")
           (peer-send h "cnode" "again" :message-id "lisp-dup-1")
           (is-equal "lisp-dup-1" (json-field (cli "peer" "recv" "--to" cep "-t" "3000") "id"))
           (is-equal 6 (nth-value 1 (cli "peer" "recv" "--to" cep "-t" "300")) "no second copy (exit 6)"))
      (uiop:terminate-process proc)
      (uiop:wait-process proc))))

(deftest interop-cli-registers-on-the-lisp-node
  (with-peers ((h "lisp-node" :token (env "POLYCALL_DEV_TOKEN")))
    (is-equal 0 (nth-value 1 (cli "peer" "register" "--to" (peer-endpoint h) "--id" "remote-c"
                                  "--peer-endpoint" "127.0.0.1:9")))
    (is-equal '(("remote-c" . "127.0.0.1:9")) (peer-list h))
    (is-equal "lisp-node" (json-field (cli "peer" "health" "--to" (peer-endpoint h)) "node_id"))))

(deftest interop-call-matches-the-cli-client
  (let* ((ep (env "POLYCALL_TEST_RPC_ENDPOINT"))
         (mine (polycall-call ep "inventory" "get" :input "{\"item_id\":\"widget-b\"}" :timeout-ms 2000)))
    (is-equal "{\"item_id\":\"widget-b\",\"quantity\":7,\"in_stock\":true}" mine)
    (is (search mine (cli "call" "inventory" "get" "--endpoint" ep "--input-value" "{\"item_id\":\"widget-b\"}")))))
