(defpackage #:lisp-polycall
  (:use #:cl)
  (:export
   ;; library
   #:*default-config*
   #:+abi-version+
   #:+wait-forever+
   #:+peer-max-payload+
   #:load-library
   #:library-path
   #:abi-version
   #:polycall-version
   #:strerror
   #:last-error
   ;; configuration (run-config keeps polycall_ffi_run_config(path, 1))
   #:run-config
   #:run-config-or-error
   #:describe-config
   ;; RPC
   #:polycall-call
   ;; peers
   #:peer
   #:peer-p
   #:make-peer
   #:peer-handle
   #:peer-open
   #:with-peer
   #:peer-close
   #:peer-endpoint
   #:peer-node-id
   #:peer-register
   #:peer-unregister
   #:peer-list
   #:peer-list-json
   #:peer-ping
   #:peer-send
   #:peer-recv
   #:peer-cancel
   #:peer-health
   #:message
   #:message-sender
   #:message-id
   #:message-payload
   ;; conditions
   #:polycall-error
   #:polycall-library-error
   #:polycall-error-status
   #:polycall-error-name
   #:polycall-error-detail
   #:polycall-error-output
   #:polycall-error-config-path
   ;; status codes
   #:+ok+ #:+e-invalid-argument+ #:+e-no-memory+ #:+e-invalid-handle+ #:+e-timeout+
   #:+e-transport+ #:+e-protocol+ #:+e-not-found+ #:+e-auth+ #:+e-remote+ #:+e-too-large+
   #:+e-busy+ #:+e-cancelled+ #:+e-config+ #:+e-address-in-use+ #:+e-unsupported+
   #:+e-permission+ #:+e-closed+ #:+e-internal+))
