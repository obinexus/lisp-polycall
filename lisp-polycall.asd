(asdf:defsystem "lisp-polycall"
  :description "Thin Common Lisp CFFI binding for libpolycall 1.5"
  :author "Nnamdi Michael Okpala <okpalan@protonmail.com>"
  :license "MIT"
  :version "1.0.0"
  :depends-on ("cffi")
  :serial t
  :components ((:file "src/package")
               (:file "src/lisp-polycall"))
  :in-order-to ((asdf:test-op (asdf:test-op "lisp-polycall/tests"))))

(asdf:defsystem "lisp-polycall/tests"
  :depends-on ("lisp-polycall")
  :serial t
  :components ((:file "tests/smoke")))
