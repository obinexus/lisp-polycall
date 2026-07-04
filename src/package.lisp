(defpackage #:lisp-polycall
  (:use #:cl)
  (:export
   #:*default-config*
   #:load-library
   #:polycall-error
   #:polycall-error-config-path
   #:polycall-error-status
   #:run-config
   #:run-config-or-error))
