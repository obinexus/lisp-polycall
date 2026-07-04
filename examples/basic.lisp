(require :asdf)
(asdf:load-system "lisp-polycall")

(let ((config-path
        (or (first (uiop:command-line-arguments))
            lisp-polycall:*default-config*)))
  (lisp-polycall:run-config-or-error config-path)
  (format t "libpolycall completed ~S successfully~%" config-path))
