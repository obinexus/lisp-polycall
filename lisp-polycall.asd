(asdf:defsystem "lisp-polycall"
  :description "Common Lisp CFFI binding for the Polycall binding ABI v1 (libpolycall >= 1.1.0)"
  :author "Nnamdi Michael Okpala <okpalan@protonmail.com>"
  :license "MIT"
  :version "1.1.0"
  :homepage "https://github.com/obinexus/lisp-polycall"
  :bug-tracker "https://github.com/obinexus/lisp-polycall/issues"
  :source-control (:git "https://github.com/obinexus/lisp-polycall.git")
  :depends-on ("cffi" "babel" "uiop")
  :serial t
  :components ((:file "src/package")
               (:file "src/lisp-polycall"))
  :in-order-to ((asdf:test-op (asdf:test-op "lisp-polycall/tests"))))

(asdf:defsystem "lisp-polycall/tests"
  :description "Real-core tests (run through tests/run-real-core.sh, which sets up the core)"
  :depends-on ("lisp-polycall" "uiop")
  :serial t
  :components ((:file "tests/real-core"))
  :perform (asdf:test-op (o c)
             (uiop:symbol-call '#:lisp-polycall/tests '#:run-tests-or-error)))
