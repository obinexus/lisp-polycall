;;;; sbcl --script examples/basic.lisp [config-path]
;;;; Validates a configuration file with the core: polycall_ffi_run_config(path, 1).
(require :asdf)
(asdf:load-asd (merge-pathnames "../lisp-polycall.asd" (or *load-truename* *default-pathname-defaults*)))
(asdf:load-system "lisp-polycall")

(let ((config-path (or (first (uiop:command-line-arguments)) lisp-polycall:*default-config*)))
  (format t "libpolycall ~A (binding ABI ~D)~%" (lisp-polycall:polycall-version) (lisp-polycall:abi-version))
  (handler-case
      (progn (lisp-polycall:run-config-or-error config-path)
             (format t "configuration is valid for running: ~A~%" config-path))
    (lisp-polycall:polycall-error (c)
      (format *error-output* "~A~%" c)
      (uiop:quit 1))))
