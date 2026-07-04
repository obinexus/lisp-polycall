(defpackage #:lisp-polycall/tests
  (:use #:cl #:lisp-polycall))

(in-package #:lisp-polycall/tests)

(assert (zerop (run-config "lisp-polycallrc")))
(assert (= 37 (run-config "__status_37__")))

(let ((captured
        (handler-case
            (progn
              (run-config-or-error "__status_37__")
              nil)
          (polycall-error (condition) condition))))
  (assert (typep captured 'polycall-error))
  (assert (= 37 (polycall-error-status captured)))
  (assert (string= "__status_37__"
                   (polycall-error-config-path captured))))

(format t "lisp-polycall Common Lisp/CFFI smoke test: PASS~%")
