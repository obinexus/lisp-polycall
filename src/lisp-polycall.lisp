(in-package #:lisp-polycall)

(defparameter *default-config* "lisp-polycallrc"
  "Default libpolycall configuration path.")

(cffi:define-foreign-library lisp-polycall-native
  (:windows (:or "lisp_polycall.dll" "lisp_polycall"))
  (:darwin (:or "liblisp_polycall.dylib" "lisp_polycall"))
  (:unix (:or "liblisp_polycall.so" "lisp_polycall"))
  (t (:default "lisp_polycall")))

(defvar *library-handle* nil)

(defun load-library (&optional pathname)
  "Load the native adapter once, optionally from PATHNAME."
  (or *library-handle*
      (setf *library-handle*
            (cffi:load-foreign-library
             (or pathname 'lisp-polycall-native)))))

(cffi:defcfun ("lisp_polycall_run_config" %run-config) :int32
  (config-path :string))

(define-condition polycall-error (error)
  ((status
    :initarg :status
    :reader polycall-error-status)
   (config-path
    :initarg :config-path
    :reader polycall-error-config-path))
  (:report
   (lambda (condition stream)
     (format stream
             "libpolycall failed with status ~D for config ~S"
             (polycall-error-status condition)
             (polycall-error-config-path condition)))))

(defun run-config (&optional (config-path *default-config*))
  "Run CONFIG-PATH and return the unchanged libpolycall status."
  (check-type config-path string)
  (load-library)
  (let ((cffi:*default-foreign-encoding* :utf-8))
    (%run-config config-path)))

(defun run-config-or-error (&optional (config-path *default-config*))
  "Run CONFIG-PATH and signal POLYCALL-ERROR for a non-zero status."
  (let ((status (run-config config-path)))
    (unless (zerop status)
      (error 'polycall-error
             :status status
             :config-path config-path))
    nil))
