;;;; lisp-polycall -- Common Lisp (CFFI) binding for the Polycall binding
;;;; ABI v1 (polycall.h, libpolycall >= 1.1.0).
;;;;
;;;; CFFI calls libpolycall directly with the exact signatures from
;;;; polycall.h. LOAD-LIBRARY resolves every symbol up front and checks
;;;; polycall_ffi_abi_version() == 1, so an old 1.0 core or a different ABI
;;;; is a POLYCALL-LIBRARY-ERROR, never an "undefined alien function" later.

(in-package #:lisp-polycall)

(defparameter *default-config* "lisp-polycallrc"
  "Default configuration path for RUN-CONFIG.")

(defconstant +abi-version+ 1)
(defconstant +wait-forever+ #xFFFFFFFF "PEER-RECV timeout: until a message, cancel or close.")
(defconstant +peer-id-max+ 64)
(defconstant +message-id-max+ 64)
(defconstant +endpoint-max+ 128)
(defconstant +peer-max-payload+ (ash 1 20))
(defconstant +call-max-output+ (ash 1 20))

(macrolet ((statuses (&rest pairs)
             `(progn
                ,@(loop for (sym val) on pairs by #'cddr
                        collect `(defconstant ,sym ,val))
                (defparameter *status-symbols* ',(loop for (sym val) on pairs by #'cddr
                                                       collect (cons val sym))))))
  (statuses +ok+ 0 +e-invalid-argument+ -1 +e-no-memory+ -2 +e-invalid-handle+ -3
            +e-timeout+ -4 +e-transport+ -5 +e-protocol+ -6 +e-not-found+ -7 +e-auth+ -8
            +e-remote+ -9 +e-too-large+ -10 +e-busy+ -11 +e-cancelled+ -12 +e-config+ -13
            +e-address-in-use+ -14 +e-unsupported+ -15 +e-permission+ -16 +e-closed+ -17
            +e-internal+ -18))

(defun status-symbol-name (status)
  "POLYCALL_E_... name without asking the library (used for loader errors)."
  (let ((sym (cdr (assoc status *status-symbols*))))
    (if sym
        (let ((s (string-trim "+" (symbol-name sym))))
          (if (string= s "OK") "POLYCALL_OK" (substitute #\_ #\- (format nil "POLYCALL_~A" s))))
        "POLYCALL_E_UNKNOWN")))

;;; ---- conditions -----------------------------------------------------------------

(define-condition polycall-error (error)
  ((status :initarg :status :reader polycall-error-status)
   (name :initarg :name :initform nil :reader polycall-error-name)
   (detail :initarg :detail :initform "" :reader polycall-error-detail)
   (output :initarg :output :initform nil :reader polycall-error-output)
   (operation :initarg :operation :initform nil :reader polycall-error-operation)
   (config-path :initarg :config-path :initform nil :reader polycall-error-config-path))
  (:report
   (lambda (c stream)
     (format stream "~@[~A: ~]~A (status=~D)~@[: ~A~]"
             (polycall-error-operation c)
             (or (polycall-error-name c) (status-symbol-name (polycall-error-status c)))
             (polycall-error-status c)
             (let ((d (polycall-error-detail c))) (and d (plusp (length d)) d)))))
  (:documentation "A failed Polycall call: STATUS (POLYCALL_E_* code), NAME (from
polycall_strerror), DETAIL (polycall_last_error of this thread) and, for
POLYCALL-CALL, OUTPUT (the remote error object); for a PEER-RECV whose
capacity was too small, OUTPUT is the needed size and the message stays queued."))

(define-condition polycall-library-error (polycall-error) ()
  (:documentation "libpolycall cannot be used: not found, not loadable, missing
binding ABI v1 symbols (an old 1.0 core) or polycall_ffi_abi_version() /= 1."))

;;; ---- loading ---------------------------------------------------------------------

(cffi:define-foreign-library libpolycall
  (:windows (:or "polycall.dll" "libpolycall.dll"))
  (:darwin "libpolycall.1.dylib")
  (:unix "libpolycall.so.1")
  (t (:default "libpolycall")))

(defparameter *symbols*
  '("polycall_get_version" "polycall_ffi_abi_version" "polycall_ffi_version" "polycall_strerror"
    "polycall_last_error" "polycall_ffi_run_config" "polycall_ffi_describe" "polycall_call"
    "polycall_peer_open" "polycall_peer_close" "polycall_peer_endpoint" "polycall_peer_node_id"
    "polycall_peer_register" "polycall_peer_unregister" "polycall_peer_list" "polycall_peer_ping"
    "polycall_peer_send" "polycall_peer_recv" "polycall_peer_cancel" "polycall_peer_health")
  "Every binding ABI v1 symbol this binding calls; all must resolve at load.")

(defvar *library* nil)
(defvar *library-path* nil)

(defun library-path () *library-path*)

(defun library-error (status fmt &rest args)
  (error 'polycall-library-error :status status :name (status-symbol-name status)
                                 :detail (apply #'format nil fmt args)
                                 :operation "load-library"))

(cffi:defcfun ("polycall_ffi_abi_version" %abi-version) :int)

(defun load-library (&optional pathname)
  "Load libpolycall once: PATHNAME, else POLYCALL_LIBRARY, else the platform
name through the OS loader path (polycall.dll / libpolycall.dll,
libpolycall.so.1, libpolycall.1.dylib). No package or parent directories
are searched."
  (or *library*
      (let* ((env (uiop:getenv "POLYCALL_LIBRARY"))
             (explicit (or (and pathname (namestring pathname))
                           (and env (plusp (length env)) env))))
        (when (and explicit (not (probe-file explicit)))
          (library-error +e-not-found+ "libpolycall library does not exist: ~A" explicit))
        (let ((lib (handler-case
                       (if explicit
                           (cffi:load-foreign-library explicit)
                           (cffi:load-foreign-library 'libpolycall))
                     (cffi:load-foreign-library-error (e)
                       (library-error +e-not-found+
                                      "libpolycall not found (~A); set POLYCALL_LIBRARY to its absolute path" e))))
              (name (or explicit "libpolycall.so.1 / polycall.dll / libpolycall.1.dylib")))
          (let ((missing (remove-if #'cffi:foreign-symbol-pointer *symbols*)))
            (when missing
              (cffi:close-foreign-library lib)
              (library-error +e-unsupported+
                             "~A is not a Polycall binding-ABI-v1 library (libpolycall >= 1.1.0 required): missing symbol~P ~{~A~^, ~}"
                             name (length missing) missing)))
          (let ((abi (%abi-version)))
            (unless (= abi +abi-version+)
              (cffi:close-foreign-library lib)
              (library-error +e-unsupported+ "~A reports binding ABI ~D; this binding requires ABI ~D"
                             name abi +abi-version+)))
          (setf *library-path* (or explicit (cffi:foreign-library-pathname lib))
                *library* lib)))))

(declaim (inline ensure-library))
(defun ensure-library () (or *library* (load-library)))

;;; ---- raw declarations (exactly polycall.h) -----------------------------------------

(cffi:defctype utf8 (:string :encoding :utf-8))

;;; CFFI's :string type rejects NIL, so the optional (nullable) const char *
;;; arguments are declared :pointer and passed through WITH-OPTIONAL-STRING.
(defmacro with-optional-string ((var value) &body body)
  "Bind VAR to NULL when VALUE is NIL, else to a NUL-terminated UTF-8 copy."
  (let ((v (gensym "VALUE")))
    `(let ((,v ,value))
       (if (null ,v)
           (let ((,var (cffi:null-pointer))) ,@body)
           (cffi:with-foreign-string (,var ,v :encoding :utf-8) ,@body)))))

(cffi:defcfun ("polycall_ffi_version" %version) :int (buf :pointer) (len :int))
(cffi:defcfun ("polycall_strerror" %strerror) utf8 (status :int))
(cffi:defcfun ("polycall_last_error" %last-error) :int (buf :pointer) (cap :size))
(cffi:defcfun ("polycall_ffi_run_config" %run-config) :int (config-path utf8) (run :int))
(cffi:defcfun ("polycall_ffi_describe" %describe) :int (config-path utf8) (buf :pointer) (len :int))
(cffi:defcfun ("polycall_call" %call) :int
  (endpoint utf8) (service utf8) (operation utf8) (input-json :pointer) (timeout-ms :uint32)
  (out :pointer) (out-cap :size) (out-len :pointer))
(cffi:defcfun ("polycall_peer_open" %peer-open) :int
  (node-id utf8) (bind-endpoint :pointer) (auth-token :pointer) (out-handle :pointer))
(cffi:defcfun ("polycall_peer_close" %peer-close) :int (h :int32))
(cffi:defcfun ("polycall_peer_endpoint" %peer-endpoint) :int (h :int32) (buf :pointer) (cap :size))
(cffi:defcfun ("polycall_peer_node_id" %peer-node-id) :int (h :int32) (buf :pointer) (cap :size))
(cffi:defcfun ("polycall_peer_register" %peer-register) :int (h :int32) (peer-id utf8) (endpoint utf8))
(cffi:defcfun ("polycall_peer_unregister" %peer-unregister) :int (h :int32) (peer-id utf8))
(cffi:defcfun ("polycall_peer_list" %peer-list) :int (h :int32) (buf :pointer) (cap :size) (out-len :pointer))
(cffi:defcfun ("polycall_peer_ping" %peer-ping) :int (h :int32) (peer utf8) (timeout-ms :uint32))
(cffi:defcfun ("polycall_peer_send" %peer-send) :int
  (h :int32) (peer utf8) (payload :pointer) (len :size) (message-id :pointer) (timeout-ms :uint32))
(cffi:defcfun ("polycall_peer_recv" %peer-recv) :int
  (h :int32) (timeout-ms :uint32) (sender :pointer) (sender-cap :size)
  (message-id :pointer) (message-id-cap :size) (payload :pointer) (payload-cap :size)
  (payload-len :pointer))
(cffi:defcfun ("polycall_peer_cancel" %peer-cancel) :int (h :int32))
(cffi:defcfun ("polycall_peer_health" %peer-health) :int (h :int32) (buf :pointer) (cap :size) (out-len :pointer))

;;; ---- helpers ------------------------------------------------------------------------

(defmacro with-buffer ((var size) &body body)
  `(let ((,var (cffi:foreign-alloc :uint8 :count (max 1 ,size))))
     (unwind-protect (progn ,@body) (cffi:foreign-free ,var))))

(defun buffer-string (buf &optional count)
  (if count
      (cffi:foreign-string-to-lisp buf :count count :encoding :utf-8)
      (cffi:foreign-string-to-lisp buf :encoding :utf-8)))

(defun timeout-ms (value)
  (cond ((eq value :infinite) +wait-forever+)
        ((and (integerp value) (<= 0 value +wait-forever+)) value)
        (t (error 'polycall-error :status +e-invalid-argument+ :name "POLYCALL_E_INVALID_ARGUMENT"
                                  :detail (format nil "timeout must be 0..~D ms or :INFINITE: ~S"
                                                  +wait-forever+ value)))))

(defun last-error ()
  "Detail of the most recent failure on this thread (\"\" after success)."
  (ensure-library)
  (with-buffer (buf 1024)
    (%last-error buf 1024)
    (buffer-string buf)))

(defun strerror (status)
  (ensure-library)
  (%strerror status))

(defun fail (status operation &key output config-path)
  ;; last_error first: nothing else may run on this thread in between
  (let* ((detail (last-error))
         (text (strerror status))
         (colon (position #\: text)))
    (error 'polycall-error :status status :name (if colon (subseq text 0 colon) text)
                           :detail detail :output output :operation operation
                           :config-path config-path)))

(defmacro check (form operation &rest keys)
  (let ((st (gensym "STATUS")))
    `(let ((,st ,form))
       (unless (zerop ,st) (fail ,st ,operation ,@keys))
       ,st)))

(defun octets (payload)
  (etypecase payload
    (string (babel:string-to-octets payload :encoding :utf-8))
    ((vector (unsigned-byte 8)) payload)
    (vector (coerce payload '(vector (unsigned-byte 8))))))

;;; ---- library / configuration / call ------------------------------------------------------

(defun abi-version ()
  (ensure-library)
  (%abi-version))

(defun polycall-version ()
  (ensure-library)
  (with-buffer (buf 64)
    (let ((n (%version buf 64)))
      (when (minusp n) (fail n "polycall_ffi_version"))
      (buffer-string buf))))

(defun run-config (&optional (config-path *default-config*) (strict t))
  "Validate CONFIG-PATH with the core grammar and return the core status
unchanged (0 = POLYCALL_OK). STRICT T (the default) is
polycall_ffi_run_config(path, 1); NIL is run=0 (unknown keys are warnings)."
  (check-type config-path string)
  (ensure-library)
  (%run-config config-path (if strict 1 0)))

(defun run-config-or-error (&optional (config-path *default-config*) (strict t))
  "Like RUN-CONFIG but signal POLYCALL-ERROR for a non-zero status."
  (let ((status (run-config config-path strict)))
    (unless (zerop status)
      (fail status (format nil "run-config ~S" config-path) :config-path config-path))
    nil))

(defun describe-config (config-path)
  "JSON description of CONFIG-PATH (secrets are never resolved)."
  (ensure-library)
  (loop with cap = 65536
        do (with-buffer (buf cap)
             (let ((n (%describe config-path buf cap)))
               (when (minusp n) (fail n (format nil "describe ~S" config-path)))
               (when (< n cap) (return (buffer-string buf n)))
               (setf cap (1+ n))))))

(defun polycall-call (endpoint service operation &key input (timeout-ms 5000))
  "One polycall_rpc v1 round trip, never retried. INPUT is JSON text or NIL
(sent as null). Returns the output JSON text."
  (ensure-library)
  (with-buffer (out +call-max-output+)
    (cffi:with-foreign-object (len :size)
      (let ((st (with-optional-string (in input)
                  (%call endpoint service operation in (timeout-ms timeout-ms)
                         out +call-max-output+ len))))
        (unless (zerop st)
          (fail st (format nil "call ~A.~A at ~A" service operation endpoint)
                :output (if (= st +e-too-large+) "" (buffer-string out))))
        (buffer-string out (cffi:mem-ref len :size))))))

;;; ---- peers ------------------------------------------------------------------------------------

(defstruct (peer (:constructor make-peer (&key handle)))
  "A Polycall peer node. Its registry and inbox belong to this node only."
  (handle 0 :type (signed-byte 64)))

(defstruct (message (:constructor make-message (sender id payload)))
  (sender "" :type string)
  (id "" :type string)
  (payload #() :type (vector (unsigned-byte 8))))

(defun peer-open (node-id &key (bind "127.0.0.1:0") token)
  "Open a node. BIND \"127.0.0.1:0\" = ephemeral port, NIL = send-only;
TOKEN NIL/\"\" = no authentication."
  (ensure-library)
  (cffi:with-foreign-object (h :int32)
    (check (with-optional-string (b bind)
             (with-optional-string (k (if (and token (plusp (length token))) token nil))
               (%peer-open node-id b k h)))
           (format nil "peer-open ~S" node-id))
    (make-peer :handle (cffi:mem-ref h :int32))))

(defun peer-close (peer)
  "Stop the listener and wake blocked receivers (POLYCALL_E_CLOSED). A second
close signals POLYCALL_E_INVALID_HANDLE."
  (ensure-library)
  (check (%peer-close (peer-handle peer)) "peer-close")
  nil)

(defmacro with-peer ((var node-id &rest args) &body body)
  `(let ((,var (peer-open ,node-id ,@args)))
     (unwind-protect (progn ,@body)
       (ignore-errors (peer-close ,var)))))

(defun %text-out (fn peer cap operation)
  (ensure-library)
  (with-buffer (buf cap)
    (check (funcall fn (peer-handle peer) buf cap) operation)
    (buffer-string buf)))

(defun peer-endpoint (peer) (%text-out #'%peer-endpoint peer +endpoint-max+ "peer-endpoint"))
(defun peer-node-id (peer) (%text-out #'%peer-node-id peer +peer-id-max+ "peer-node-id"))

(defun peer-register (peer peer-id endpoint)
  (ensure-library)
  (check (%peer-register (peer-handle peer) peer-id endpoint) (format nil "peer-register ~S" peer-id))
  t)

(defun peer-unregister (peer peer-id)
  (ensure-library)
  (check (%peer-unregister (peer-handle peer) peer-id) (format nil "peer-unregister ~S" peer-id))
  t)

(defun %sized-json (fn peer operation)
  (ensure-library)
  (let ((cap 4096))
    (loop repeat 4
          do (with-buffer (buf cap)
               (cffi:with-foreign-object (len :size)
                 (let ((st (funcall fn (peer-handle peer) buf cap len)))
                   (cond ((zerop st) (return-from %sized-json (buffer-string buf (cffi:mem-ref len :size))))
                         ((= st +e-too-large+) (setf cap (1+ (cffi:mem-ref len :size))))
                         (t (fail st operation)))))))
    (fail +e-too-large+ operation)))

(defun peer-list-json (peer) (%sized-json #'%peer-list peer "peer-list"))
(defun peer-health (peer) (%sized-json #'%peer-health peer "peer-health"))

(defun peer-list (peer)
  "This node's registry as an alist ((peer-id . endpoint) ...). Ids are
[A-Za-z0-9._-] and endpoints host:port, so the JSON has no escapes."
  (let ((json (peer-list-json peer)) (pairs '()) (pos 0))
    (flet ((next-string ()
             (let* ((a (position #\" json :start pos))
                    (b (and a (position #\" json :start (1+ a)))))
               (when b (setf pos (1+ b)) (subseq json (1+ a) b)))))
      (loop for key = (next-string)
            for value = (and key (next-string))
            while value do (push (cons key value) pairs)))
    (nreverse pairs)))

(defun peer-ping (peer target &key (timeout-ms 2000))
  (ensure-library)
  (check (%peer-ping (peer-handle peer) target (timeout-ms timeout-ms)) (format nil "peer-ping ~S" target))
  t)

(defun peer-send (peer target payload &key message-id (timeout-ms 5000))
  "Deliver PAYLOAD (octet vector, or a string sent UTF-8 encoded; <= 1 MiB)
to TARGET (registered id or host:port): exactly one attempt. Retry with the
SAME MESSAGE-ID; the receiver drops duplicates."
  (ensure-library)
  (let* ((bytes (octets payload))
         (n (length bytes)))
    (with-buffer (buf n)
      (dotimes (i n) (setf (cffi:mem-aref buf :uint8 i) (aref bytes i)))
      (check (with-optional-string (m (if (and message-id (plusp (length message-id))) message-id nil))
               (%peer-send (peer-handle peer) target buf n m (timeout-ms timeout-ms)))
             (format nil "peer-send to ~S" target))))
  t)

(defun peer-recv (peer &key (timeout-ms +wait-forever+) (capacity +peer-max-payload+))
  "Take the oldest message as a MESSAGE (sender, id, octet payload).
TIMEOUT-MS 0 polls; :INFINITE / +WAIT-FOREVER+ waits for a message,
PEER-CANCEL or PEER-CLOSE."
  (ensure-library)
  (with-buffer (buf capacity)
    (cffi:with-foreign-objects ((sender :char +peer-id-max+) (mid :char +message-id-max+) (len :size))
      (let* ((st (%peer-recv (peer-handle peer) (timeout-ms timeout-ms) sender +peer-id-max+
                             mid +message-id-max+ buf capacity len))
             (n (cffi:mem-ref len :size)))
        (when (= st +e-too-large+)
          (fail st "peer-recv" :output n))
        (check st "peer-recv")
        (let ((payload (make-array n :element-type '(unsigned-byte 8))))
          (dotimes (i n) (setf (aref payload i) (cffi:mem-aref buf :uint8 i)))
          (make-message (buffer-string sender) (buffer-string mid) payload))))))

(defun peer-cancel (peer)
  "Wake every PEER-RECV blocked on PEER with POLYCALL_E_CANCELLED."
  (ensure-library)
  (check (%peer-cancel (peer-handle peer)) "peer-cancel")
  nil)
