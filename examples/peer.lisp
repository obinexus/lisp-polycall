;;;; sbcl --script examples/peer.lisp
;;;; Two peer nodes in one process exchange a payload in each direction.
(require :asdf)
(asdf:load-asd (merge-pathnames "../lisp-polycall.asd" (or *load-truename* *default-pathname-defaults*)))
(asdf:load-system "lisp-polycall")
(use-package :lisp-polycall)

(with-peer (alpha "alpha")                            ; listens on 127.0.0.1:<ephemeral>
  (with-peer (beta "beta")
    (peer-register alpha "beta" (peer-endpoint beta)) ; alpha's registry only
    (peer-send alpha "beta" "hello beta" :message-id "greeting-1")
    (let ((m (peer-recv beta :timeout-ms 2000)))
      (format t "beta got ~D bytes from ~A (id ~A)~%"
              (length (message-payload m)) (message-sender m) (message-id m)))
    (peer-send beta (peer-endpoint alpha) "hello alpha" :message-id "greeting-2")
    (format t "alpha got ~A~%"
            (babel:octets-to-string (message-payload (peer-recv alpha :timeout-ms 2000))))))
