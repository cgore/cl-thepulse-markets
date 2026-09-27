;;;; Copyright (c) 2026, Christopher Mark Gore,
;;;; Soli Deo Gloria,
;;;; All rights reserved.
;;;;
;;;; 22 Forest Glade Court, Saint Charles, Missouri 63304 USA.
;;;; Web: http://cgore.com
;;;; Email: cgore@cgore.com
;;;;
;;;; Redistribution and use in source and binary forms, with or without
;;;; modification, are permitted provided that the following conditions are met:
;;;;
;;;;     * Redistributions of source code must retain the above copyright
;;;;       notice, this list of conditions and the following disclaimer.
;;;;
;;;;     * Redistributions in binary form must reproduce the above copyright
;;;;       notice, this list of conditions and the following disclaimer in the
;;;;       documentation and/or other materials provided with the distribution.
;;;;
;;;;     * Neither the name of Christopher Mark Gore nor the names of other
;;;;       contributors may be used to endorse or promote products derived from
;;;;       this software without specific prior written permission.
;;;;
;;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
;;;; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
;;;; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;;;; ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
;;;; LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
;;;; CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
;;;; SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;;;; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
;;;; CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
;;;; ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
;;;; POSSIBILITY OF SUCH DAMAGE.

(defpackage #:thepulse-markets/rest-api
  (:use :common-lisp :sigma/behave)
  (:export :*api*
           :*api-key*
           :*user-agent*
           :*api-cache-timeout-seconds*
           :*pubkey-cache-timeout-seconds*
           :*request-timeout-seconds*
           :*max-retries*
           :*retry-wait-seconds*
           :*sample-symbols*
           :*public-paths*
           :*placeholder-keys*
           :use-key
           :use-keyless
           :local-configuration-path
           :reload-local-configuration
           :configure-from-environment
           :usable-key-p
           :sample-symbol-p
           :public-path-p
           :canonicalize-symbol
           :canonicalize-symbols
           :canonicalize-interval
           :canonicalize-dataset
           :unix-epoch
           :unix->universal
           :universal->unix
           :parse-iso-8601
           :format-iso-8601
           :canonicalize-time
           :query-value
           :query
           :query-alist
           :v1
           :api-uri
           :json-elt
           :json-ref
           :json-list
           :json-true-p
           :json-false-p
           :http-get
           :http-get-json
           :http-get-json-cached
           :http-get-json-do-not-cache
           :api-get
           :http-status
           :http-body
           :api-error
           :rate-limited
           :monthly-limit
           :unauthorized
           :plan-restricted
           :unsupported-symbol
           :service-unavailable
           :needs-key
           :api-error-status
           :api-error-url
           :api-error-code
           :api-error-message
           :api-error-timestamp
           :api-error-body
           :classify-error
           :api-error-from
           :get-health
           :get-pubkey
           :get-status
           :get-symbols
           :get-uptime
           :get-terms
           :get-incidents
           :get-speed
           :get-sample
           :get-price
           :get-batch
           :get-print
           :get-metadata
           :get-history
           :get-research-compare
           :get-source-health
           :get-verity-price
           :get-verity-batch
           :get-verity-catalog
           :get-verity-venues
           :get-verity-status))
(in-package :thepulse-markets/rest-api)

(defvar *api* "https://mcp.thepulse.markets"
  "Pulse Verity Index origin.  Paths are under /api/index/v1/.")

(defvar *api-key* nil
  "Developer key (pidx_...).  On load, source/configuration/local-configuration.lisp
sets this when that file exists.  Otherwise PULSE_API_KEY, then
THEPULSE_MARKETS_API_KEY.  Sent as Authorization: Bearer on keyed calls.
Public reads and the BTC/ETH/SOL sample do not send it.")

(defvar *user-agent* "thepulse-markets/0.1.0 (Common Lisp)")

(defvar *api-cache-timeout-seconds* 60
  "How long HTTP-GET-JSON-CACHED keeps a response.  Live price calls
default to :CACHE NIL; this layer is for reference data.")
(defvar *pubkey-cache-timeout-seconds* 300
  "How long GET-PUBKEY keeps the verification-key ring.")
(defvar *request-timeout-seconds* 15)
(defvar *max-retries* 3
  "Attempts for HTTP 429 RATE_LIMITED.  MONTHLY_LIMIT is not retried.")
(defvar *retry-wait-seconds* 2
  "Base wait between 429 retries.  Attempt N waits N times this, unless
Retry-After is shorter.  Retry-After above 30 seconds is not slept.")

(defvar *sample-symbols* '("BTC" "ETH" "SOL")
  "Symbols the keyless /sample endpoint will answer.")

(defvar *placeholder-keys*
  '("pidx_your_key_here" "your_key_here" "your_api_key" "your-api-key"
    "pidx_" "changeme" "xxx" "none" "null" "undefined")
  "Copy-paste placeholders.  USABLE-KEY-P treats these as no key.")

(defvar *public-paths*
  '("/api/index/v1/health"
    "/api/index/v1/pubkey"
    "/api/index/v1/status"
    "/api/index/v1/symbols"
    "/api/index/v1/uptime"
    "/api/index/v1/terms"
    "/api/index/v1/incidents"
    "/api/index/v1/speed"
    "/api/index/v1/sample"
    "/api/index/v1/verity/venues"
    "/api/index/v1/verity/status")
  "Paths that do not require a key and do not receive one.
Sending a key on a public read can meter the call, so these stay keyless.")

(defun v1 (suffix)
  "Path for a /api/index/v1/ endpoint.  SUFFIX is \"price\" or \"verity/catalog\"."
  (concatenate 'string "/api/index/v1/" suffix))

(defun use-key (key)
  "Use KEY for keyed calls.  Returns KEY."
  (setf *api-key* key))

(defun use-keyless ()
  "Clear *API-KEY*.  PRICE still answers BTC, ETH, and SOL."
  (setf *api-key* nil))

(defun local-configuration-path ()
  "Gitignored Lisp file that may rebind *API-KEY* and the other parameters.
Loaded in this package, same idea as limbic.fi's local-configuration.lisp."
  (merge-pathnames #P"source/configuration/local-configuration.lisp"
                   (asdf:system-source-directory :thepulse-markets)))

(defun reload-local-configuration ()
  "Load the local configuration file when it exists.  Returns the pathname
or NIL.  A missing file is the normal case for everyone but the machine
that keeps the key there."
  (let ((path (local-configuration-path)))
    (when (probe-file path)
      (load path)
      path)))

(defun configure-from-environment ()
  "Set *API-KEY* from PULSE_API_KEY, else THEPULSE_MARKETS_API_KEY,
when the image does not already have a usable key.  A key from
local-configuration.lisp wins.  The environment is the backup."
  (unless (usable-key-p *api-key*)
    (let ((pulse (uiop:getenv "PULSE_API_KEY"))
          (local (uiop:getenv "THEPULSE_MARKETS_API_KEY")))
      (cond ((usable-key-p pulse) (setf *api-key* pulse))
            ((usable-key-p local) (setf *api-key* local)))))
  *api-key*)

(defun placeholder-key-p (key)
  (or (search "${" key)
      (member key *placeholder-keys* :test #'string-equal)))

(defun usable-key-p (key)
  "True when KEY can be sent as a Bearer token.
Empty, whitespace, unexpanded ${...} templates, and the documented
placeholders are not keys.  The keyless sample is used instead."
  (and (stringp key)
       (plusp (length key))
       (not (find-if (lambda (char)
                       (or (char= char #\Space)
                           (char= char #\Tab)
                           (char= char #\Newline)
                           (char= char #\Return)
                           (< (char-code char) 32)))
                     key))
       (not (placeholder-key-p key))))

(defun public-path-p (path)
  (member path *public-paths* :test #'string=))

(defun sample-symbol-p (symbol)
  (member (canonicalize-symbol symbol) *sample-symbols* :test #'string=))

(defun require-key (path)
  "Signal NEEDS-KEY when PATH is keyed and *API-KEY* is not usable."
  (unless (or (public-path-p path) (usable-key-p *api-key*))
    (error 'needs-key
           :url (concatenate 'string *api* path)
           :error-message
           "This request needs a Pulse developer key. Put (defparameter *api-key* \"pidx_...\") in source/configuration/local-configuration.lisp, or set PULSE_API_KEY. PRICE still answers BTC, ETH, and SOL with no key. Keys are created at https://thepulse.markets/developers.")))

(behavior 'usable-key-p
  (should-be-false (usable-key-p nil))
  (should-be-false (usable-key-p ""))
  (should-be-false (usable-key-p "pidx_your_key_here"))
  (should-be-false (usable-key-p "${user_config.pulse_api_key}"))
  (should-be-false (usable-key-p "pidx_ abc"))
  (should-be-true (usable-key-p "pidx_abc")))

(behavior 'use-key
  (let ((*api-key* nil))
    (use-key "pidx_abc")
    (should-string= "pidx_abc" *api-key*)
    (should-be-true (usable-key-p *api-key*))
    (use-keyless)
    (should-be-null *api-key*)
    (should-be-true (public-path-p "/api/index/v1/pubkey"))))

;;;; -- Symbols and query strings ---------------------------------------------

(defun canonicalize-symbol (symbol)
  "Pulse tickers are uppercase: BTC, ETH, 1000SATS."
  (let ((raw (cond ((null symbol) nil)
                   ((stringp symbol)
                    (string-trim '(#\Space #\Tab #\Newline #\Return) symbol))
                   ((symbolp symbol) (symbol-name symbol))
                   (t (string-trim '(#\Space #\Tab #\Newline #\Return)
                                   (princ-to-string symbol))))))
    (when (and raw (plusp (length raw)))
      (string-upcase raw))))

(defun split-comma (string)
  "Split STRING on commas and trim whitespace.  Empty pieces drop."
  (loop for start = 0 then (1+ pos)
        for pos = (position #\, string :start start)
        for piece = (string-trim '(#\Space #\Tab #\Newline #\Return)
                                 (subseq string start pos))
        when (plusp (length piece))
          collect piece
        while pos))

(defun canonicalize-symbols (symbols)
  "Uppercase symbols from a symbol, a comma string, or a list.
Duplicates drop, order kept."
  (let* ((raw (cond ((null symbols) nil)
                    ((and (stringp symbols) (find #\, symbols))
                     (split-comma symbols))
                    ((or (stringp symbols) (symbolp symbols))
                     (list symbols))
                    ((listp symbols) symbols)
                    ((and (vectorp symbols) (not (stringp symbols)))
                     (coerce symbols 'list))
                    (t (list symbols))))
         (seen (make-hash-table :test #'equal)))
    (loop for item in raw
          for ticker = (canonicalize-symbol item)
          when (and ticker (not (gethash ticker seen)))
            collect (progn (setf (gethash ticker seen) t) ticker))))

(defun canonicalize-interval (interval)
  "Pulse history intervals are 1m, 5m, 1h, and 1d.
Short names m/h/d and a few words map onto those.  Anything else is
downcased and passed through."
  (when interval
    (let ((name (string-downcase
                 (cond ((stringp interval) interval)
                       ((symbolp interval) (symbol-name interval))
                       (t (princ-to-string interval))))))
      (cond ((member name '("1m" "m" "min" "minute") :test #'string=) "1m")
            ((string= name "5m") "5m")
            ((member name '("1h" "h" "hour" "hourly" "60m") :test #'string=) "1h")
            ((member name '("1d" "d" "day" "daily") :test #'string=) "1d")
            (t name)))))

(defparameter unix-epoch (encode-universal-time 0 0 0 1 1 1970 0)
  "Universal time of 1970-01-01T00:00:00Z.")

(defun unix->universal (unix)
  "UNIX seconds or milliseconds to universal time.
Values above 10^11 are milliseconds."
  (when (numberp unix)
    (let ((seconds (if (> unix 100000000000)
                       (floor unix 1000)
                       (floor unix))))
      (+ seconds unix-epoch))))

(defun universal->unix (universal)
  "Universal time to UNIX seconds."
  (- universal unix-epoch))

(defun coerce-universal (value)
  "Integer VALUE to a universal time.
Above 10^11: UNIX milliseconds.  Above 3*10^9: already universal.
Otherwise UNIX seconds.  Same thresholds as cl-coingecko."
  (cond ((> value 100000000000) (unix->universal value))
        ((> value 3000000000) value)
        (t (unix->universal value))))

(defun format-iso-8601 (universal)
  "Universal time as YYYY-MM-DDTHH:MM:SSZ."
  (multiple-value-bind (second minute hour day month year)
      (decode-universal-time universal 0)
    (format nil "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0DZ"
            year month day hour minute second)))

(defun iso-offset-seconds (rest)
  "Seconds east of UTC encoded in the suffix of an ISO-8601 timestamp.
REST is the text after YYYY-MM-DDTHH:MM:SS, such as \".981Z\" or \"+05:30\"."
  (let ((pos (position-if (lambda (char)
                            (member char '(#\Z #\z #\+ #\-) :test #'char=))
                          rest)))
    (cond ((or (null pos)
               (char= (char rest pos) #\Z)
               (char= (char rest pos) #\z))
           0)
          (t
           (let* ((sign (if (char= (char rest pos) #\-) -1 1))
                  (digits (subseq rest (1+ pos)))
                  (hour 0)
                  (minute 0))
             (cond ((and (>= (length digits) 5)
                         (char= (char digits 2) #\:))
                    (setf hour (parse-integer digits :start 0 :end 2)
                          minute (parse-integer digits :start 3 :end 5)))
                   ((>= (length digits) 4)
                    (setf hour (parse-integer digits :start 0 :end 2)
                          minute (parse-integer digits :start 2 :end 4)))
                   ((>= (length digits) 2)
                    (setf hour (parse-integer digits :end 2))))
             (* sign (+ (* hour 3600) (* minute 60))))))))

(defun parse-iso-8601 (string)
  "Universal time of an ISO-8601 timestamp.  Fractional seconds are truncated.
Z and numeric offsets are accepted.  NIL when STRING is not a timestamp."
  (when (and (stringp string) (>= (length string) 19))
    (handler-case
        (let ((year (parse-integer string :start 0 :end 4))
              (month (parse-integer string :start 5 :end 7))
              (day (parse-integer string :start 8 :end 10))
              (hour (parse-integer string :start 11 :end 13))
              (minute (parse-integer string :start 14 :end 16))
              (second (parse-integer string :start 17 :end 19)))
          (unless (and (char= (char string 4) #\-)
                       (char= (char string 7) #\-)
                       (member (char string 10) '(#\T #\t) :test #'char=)
                       (char= (char string 13) #\:)
                       (char= (char string 16) #\:))
            (return-from parse-iso-8601 nil))
          (- (encode-universal-time second minute hour day month year 0)
             (iso-offset-seconds (subseq string 19))))
      (error () nil))))

(defun canonicalize-time (value)
  "ISO-8601 UTC string for a query parameter.
Strings pass through.  Integers are UNIX seconds, UNIX milliseconds,
or universal times.  NIL stays NIL so QUERY can drop it."
  (cond ((null value) nil)
        ((stringp value) value)
        ((integerp value) (format-iso-8601 (coerce-universal value)))
        (t (error "Time must be an ISO-8601 string, a UNIX time, or a universal time. Got ~S."
                  value))))

(defun canonicalize-dataset (dataset)
  "History datasets are verified and reconstructed."
  (when dataset
    (let ((name (string-downcase
                 (cond ((stringp dataset) dataset)
                       ((symbolp dataset) (symbol-name dataset))
                       (t (princ-to-string dataset))))))
      (cond ((member name '("verified" "verify") :test #'string=) "verified")
            ((member name '("reconstructed" "reconstruct") :test #'string=)
             "reconstructed")
            (t name)))))

(defun query-value (value)
  "Turn a Lisp value into a query-string fragment.
Lists become comma-separated.  T/:TRUE and :FALSE become true/false.
Symbols are downcased.  NIL drops.  Strings pass through unchanged,
so an already-uppercased ticker stays uppercased."
  (cond ((eq value t)      "true")
        ((eq value :true)  "true")
        ((eq value :false) "false")
        ((eq value yason:true) "true")
        ((eq value yason:false) "false")
        ((null value)      nil)
        ((stringp value)   value)
        ((symbolp value)   (string-downcase (symbol-name value)))
        ((and (vectorp value) (not (stringp value)))
         (query-value (coerce value 'list)))
        ((listp value)
         (format nil "~{~A~^,~}" (mapcar #'query-value value)))
        (t (princ-to-string value))))

(defun query (&rest pairs)
  "Build a query list of (NAME VALUE) pairs from NAME VALUE ..., dropping NILs.
Pairs are proper lists so function-cache can hash them; HTTP-GET turns them
into an alist for QURI."
  (loop for (name value) on pairs by #'cddr
        for rendered = (query-value value)
        when rendered
          collect (list name rendered)))

(defun query-alist (query-args)
  (mapcar (lambda (pair)
            (if (and (consp pair) (consp (cdr pair)))
                (cons (first pair) (second pair))
                pair))
          query-args))

(defun api-uri (path &rest pairs)
  "Absolute URL for PATH and NAME VALUE query pairs.  NILs drop."
  (quri:render-uri
   (quri:make-uri :defaults (concatenate 'string *api* path)
                  :query (query-alist (apply #'query pairs)))))

(behavior 'canonicalize-symbol
  (should-string= "BTC" (canonicalize-symbol "btc"))
  (should-string= "BTC" (canonicalize-symbol :btc))
  (should-string= "1000SATS" (canonicalize-symbol "1000sats"))
  (should-be-null (canonicalize-symbol nil))
  (should-be-null (canonicalize-symbol "  "))
  (should-be-true (sample-symbol-p :eth))
  (should-be-false (sample-symbol-p "DOGE")))

(behavior 'canonicalize-symbols
  (should-equal '("BTC") (canonicalize-symbols :btc))
  (should-equal '("BTC" "ETH") (canonicalize-symbols "btc, ETH, btc"))
  (should-equal '("BTC" "ETH") (canonicalize-symbols '(:btc "eth")))
  (should-equal '() (canonicalize-symbols nil))
  (should-equal '() (canonicalize-symbols " , ")))

(behavior 'canonicalize-interval
  (should-string= "1m" (canonicalize-interval :m))
  (should-string= "1m" (canonicalize-interval "1M"))
  (should-string= "5m" (canonicalize-interval "5m"))
  (should-string= "1h" (canonicalize-interval :h))
  (should-string= "1d" (canonicalize-interval "D"))
  (should-string= "2h" (canonicalize-interval "2h"))
  (should-be-null (canonicalize-interval nil)))

(behavior 'canonicalize-dataset
  (should-string= "verified" (canonicalize-dataset :verified))
  (should-string= "reconstructed" (canonicalize-dataset "Reconstructed"))
  (should-be-null (canonicalize-dataset nil)))

(behavior 'parse-iso-8601
  (let ((noon (encode-universal-time 0 0 12 26 9 2026 0)))
    (should= unix-epoch (unix->universal 0))
    (should= 0 (universal->unix unix-epoch))
    (should= noon (parse-iso-8601 "2026-09-26T12:00:00Z"))
    (should= noon (parse-iso-8601 "2026-09-26T12:00:00.981Z"))
    (should= (parse-iso-8601 "2026-09-26T06:30:00Z")
             (parse-iso-8601 "2026-09-26T12:00:00+05:30"))
    (should-string= "2026-09-26T12:00:00Z" (format-iso-8601 noon))
    (should-string= "2026-09-26T12:00:00Z" (canonicalize-time noon))
    (should-string= "1970-01-01T00:00:00Z" (canonicalize-time 0))
    (should-be-null (parse-iso-8601 "not-a-time"))
    (should-be-null (canonicalize-time nil))))

(behavior 'query-value
  (spec "booleans"
    (should-string= "true" (query-value t))
    (should-string= "true" (query-value :true))
    (should-string= "false" (query-value :false)))
  (spec "symbols and strings"
    (should-string= "real-time" (query-value :real-time))
    (should-string= "BTC" (query-value "BTC")))
  (spec "csv lists"
    (should-string= "BTC,ETH" (query-value '("BTC" "ETH"))))
  (spec "numbers"
    (should-string= "0" (query-value 0))
    (should-string= "2" (query-value 2)))
  (spec "null"
    (should-be-null (query-value nil))))

(behavior 'query
  (should-equal '(("symbol" "BTC") ("limit" "2"))
                (query "symbol" "BTC" "cursor" nil "limit" 2))
  (should-be-null (query "missing" nil)))

(behavior 'v1
  (should-string= "/api/index/v1/price" (v1 "price"))
  (should-string= "/api/index/v1/verity/catalog" (v1 "verity/catalog")))

;;;; -- JSON walking ----------------------------------------------------------

(defun json-elt (seq index)
  "Element INDEX of a Yason vector or list, or NIL."
  (cond ((null seq) nil)
        ((and (vectorp seq) (not (stringp seq))
              (integerp index) (<= 0 index) (< index (length seq)))
         (aref seq index))
        ((and (listp seq) (integerp index) (<= 0 index))
         (nth index seq))
        (t nil)))

(defun json-ref (object &rest keys)
  "Walk OBJECT by hash keys (strings) and vector/list indices (integers)."
  (dolist (key keys object)
    (setf object
          (cond ((null object) nil)
                ((and (hash-table-p object) (not (integerp key)))
                 (gethash key object))
                ((integerp key) (json-elt object key))
                (t nil)))))

(defun json-list (value)
  "JSON array as a list.  NIL when VALUE is not an array."
  (cond ((null value) nil)
        ((stringp value) nil)
        ((vectorp value) (coerce value 'list))
        ((listp value) value)
        (t nil)))

(defun json-true-p (value)
  (or (eq value t)
      (eq value :true)
      (eq value yason:true)))

(defun json-false-p (value)
  (or (eq value :false)
      (eq value yason:false)))

(behavior 'json-ref
  (let* ((yason:*parse-json-arrays-as-vectors* t)
         (yason:*parse-json-booleans-as-symbols* t)
         (obj (yason:parse "{\"pagination\":{\"truncated\":true,\"rows\":[{\"symbol\":\"BTC\"}]}}")))
    (should-be-true (json-true-p (json-ref obj "pagination" "truncated")))
    (should-string= "BTC" (json-ref obj "pagination" "rows" 0 "symbol"))))

;;;; -- Error conditions ------------------------------------------------------
;; Failures are an HTTP error whose JSON body looks like:
;;   {"success": false, "code": "UNSUPPORTED_SYMBOL", "message": "..."}
;; 429 is either RATE_LIMITED (wait) or MONTHLY_LIMIT (do not retry).
;; Some refusals arrive as HTTP 200 with success:false.  Those are signaled
;; the same way, with status 200.

(define-condition api-error (error)
  ((status :initform nil :initarg :status :reader api-error-status)
   (url :initform nil :initarg :url :reader api-error-url)
   (error-code :initform nil :initarg :error-code :reader api-error-code)
   (error-message :initform nil :initarg :error-message :reader api-error-message)
   (timestamp :initform nil :initarg :timestamp :reader api-error-timestamp)
   (body :initform nil :initarg :body :reader api-error-body))
  (:report (lambda (condition stream)
             (format stream "Pulse API error [HTTP ~A~A]: ~A (url: ~A)"
                     (or (api-error-status condition) "?")
                     (if (api-error-code condition)
                         (format nil ", code ~A" (api-error-code condition))
                         "")
                     (or (api-error-message condition) "unknown error")
                     (or (api-error-url condition) "?"))))
  (:documentation "An error returned by the Pulse Verity Index API.
STATUS is the HTTP status (200 when the body itself says success:false).
ERROR-CODE and ERROR-MESSAGE come from the JSON body.  URL is the request.
BODY is the raw response text."))

(define-condition rate-limited (api-error) ()
  (:documentation "HTTP 429 RATE_LIMITED.  Wait and retry.  Not the monthly cap."))

(define-condition monthly-limit (api-error) ()
  (:documentation "HTTP 429 MONTHLY_LIMIT.  The allowance resets at the next
UTC month.  A new key does not reset it.  This client does not retry it."))

(define-condition unauthorized (api-error) ()
  (:documentation "HTTP 401.  The key was missing or refused."))

(define-condition plan-restricted (api-error) ()
  (:documentation "HTTP 403.  The key's plan cannot call this endpoint.
History, research, and source health are plan-gated."))

(define-condition unsupported-symbol (api-error) ()
  (:documentation "The symbol is not in the served universe.
GET-SYMBOLS lists what is.  A batch puts this on the row instead of failing
the whole call."))

(define-condition service-unavailable (api-error) ()
  (:documentation "HTTP 503.  The index is below its quality floors.
GET-HEALTH is the probe; an unavailable price is not zero."))

(define-condition needs-key (api-error) ()
  (:report (lambda (condition stream)
             (format stream "~A"
                     (or (api-error-message condition)
                         "A Pulse API key is required."))))
  (:documentation "A keyed call was made with no usable *API-KEY*.
PRICE of BTC, ETH, or SOL still works, via the sample endpoint."))

(behavior 'require-key
  (let ((*api-key* nil))
    (handler-case (require-key "/api/index/v1/price")
      (needs-key (condition)
        (should-be-true (search "PULSE_API_KEY" (api-error-message condition))))
      (:no-error (&rest ignored)
        (declare (ignore ignored))
        (should-be-true nil)))
    (let ((*api-key* "pidx_abc"))
      (should-be-true (usable-key-p *api-key*)))))

(defun http-status (condition)
  (let ((fn (or (and (find-symbol "RESPONSE-STATUS" :dexador)
                     (fboundp (find-symbol "RESPONSE-STATUS" :dexador))
                     (symbol-function (find-symbol "RESPONSE-STATUS" :dexador)))
                (and (find-symbol "RESPONSE-STATUS" :dex)
                     (fboundp (find-symbol "RESPONSE-STATUS" :dex))
                     (symbol-function (find-symbol "RESPONSE-STATUS" :dex))))))
    (when fn
      (ignore-errors (funcall fn condition)))))

(defun http-body (condition)
  "The response body of a dexador/dex response condition, if any."
  (let ((fn (or (and (find-symbol "RESPONSE-BODY" :dexador)
                     (fboundp (find-symbol "RESPONSE-BODY" :dexador))
                     (symbol-function (find-symbol "RESPONSE-BODY" :dexador)))
                (and (find-symbol "RESPONSE-BODY" :dex)
                     (fboundp (find-symbol "RESPONSE-BODY" :dex))
                     (symbol-function (find-symbol "RESPONSE-BODY" :dex))))))
    (when fn
      (ignore-errors (funcall fn condition)))))

(defun http-headers (condition)
  (let ((fn (or (and (find-symbol "RESPONSE-HEADERS" :dexador)
                     (fboundp (find-symbol "RESPONSE-HEADERS" :dexador))
                     (symbol-function (find-symbol "RESPONSE-HEADERS" :dexador)))
                (and (find-symbol "RESPONSE-HEADERS" :dex)
                     (fboundp (find-symbol "RESPONSE-HEADERS" :dex))
                     (symbol-function (find-symbol "RESPONSE-HEADERS" :dex))))))
    (when fn
      (ignore-errors (funcall fn condition)))))

(defun ensure-text (body)
  (cond ((or (null body) (stringp body)) body)
        ((typep body '(vector (unsigned-byte 8)))
         (babel:octets-to-string body :encoding :utf-8))
        (t (princ-to-string body))))

(defun parse-json-text (text)
  (let ((yason:*parse-json-arrays-as-vectors* t)
        (yason:*parse-json-booleans-as-symbols* t))
    (yason:parse text)))

(defun error-fields (body)
  "CODE and MESSAGE from a Pulse error body, or NIL NIL."
  (let ((text (ensure-text body)))
    (when (and (stringp text) (plusp (length text))
               (char= (char (string-left-trim '(#\Space #\Tab #\Newline) text) 0)
                      #\{))
      (ignore-errors
        (let ((top (parse-json-text text)))
          (when (hash-table-p top)
            (values (gethash "code" top)
                    (gethash "message" top))))))))

(defun code-is (code expected)
  (and (stringp code) (string-equal code expected)))

(defun classify-error (status code)
  "Pick the api-error subclass for HTTP STATUS and Pulse CODE."
  (cond ((code-is code "MONTHLY_LIMIT") 'monthly-limit)
        ((and (integerp status) (= status 429)) 'rate-limited)
        ((and (integerp status) (= status 401)) 'unauthorized)
        ((and (integerp status) (= status 403)) 'plan-restricted)
        ((and (integerp status) (= status 503)) 'service-unavailable)
        ((code-is code "UNSUPPORTED_SYMBOL") 'unsupported-symbol)
        (t 'api-error)))

(defun uri-string (uri)
  (if (stringp uri)
      uri
      (quri:render-uri uri)))

(defun api-error-from (status body url)
  "Build the api-error for HTTP STATUS and response BODY."
  (multiple-value-bind (code message) (error-fields body)
    (let ((url (uri-string url)))
      (make-instance (classify-error status code)
                     :status status
                     :url url
                     :error-code code
                     :error-message (or message
                                       (format nil "HTTP status ~A from ~A"
                                               status url))
                     :body (ensure-text body)))))

(defun api-refusal-p (payload)
  (and (hash-table-p payload)
       (json-false-p (gethash "success" payload))))

(defun header-value (headers name)
  (cond ((hash-table-p headers)
         (or (gethash name headers)
             (gethash (string-downcase name) headers)
             (loop for key being the hash-keys of headers
                   using (hash-value value)
                   when (and (stringp key) (string-equal key name))
                     return value)))
        ((listp headers)
         (cdr (assoc name headers :test #'string-equal)))))

(defun retry-after-seconds (condition)
  "Retry-After in seconds, when it is an integer from 1 to 30."
  (let* ((headers (http-headers condition))
         (raw (and headers (header-value headers "retry-after"))))
    (when (and (stringp raw) (plusp (length raw)) (every #'digit-char-p raw))
      (let ((n (parse-integer raw)))
        (when (<= 1 n 30) n)))))

(behavior 'classify-error
  (should-eq 'monthly-limit (classify-error 429 "MONTHLY_LIMIT"))
  (should-eq 'rate-limited (classify-error 429 "RATE_LIMITED"))
  (should-eq 'rate-limited (classify-error 429 nil))
  (should-eq 'unauthorized (classify-error 401 "NO_KEY"))
  (should-eq 'plan-restricted (classify-error 403 nil))
  (should-eq 'service-unavailable (classify-error 503 nil))
  (should-eq 'unsupported-symbol (classify-error 404 "UNSUPPORTED_SYMBOL"))
  (should-eq 'unsupported-symbol (classify-error 200 "UNSUPPORTED_SYMBOL"))
  (should-eq 'api-error (classify-error 400 "BAD_QUERY")))

(behavior 'api-error-from
  (let ((condition (api-error-from
                    404
                    "{\"success\":false,\"code\":\"UNSUPPORTED_SYMBOL\",\"message\":\"nope\"}"
                    "https://mcp.thepulse.markets/api/index/v1/price?symbol=NOPE")))
    (should-be-true (typep condition 'unsupported-symbol))
    (should= 404 (api-error-status condition))
    (should-string= "UNSUPPORTED_SYMBOL" (api-error-code condition))
    (should-string= "nope" (api-error-message condition))))

;;;; -- HTTP ------------------------------------------------------------------

(defun request-headers ()
  (list (cons "Accept" "application/json")
        (cons "User-Agent" *user-agent*)))

(defun send-key-p (path)
  "Send the bearer token only on keyed paths, and only when it is usable.
Public paths stay keyless so a status poll does not meter the account."
  (and (usable-key-p *api-key*)
       (not (public-path-p path))))

(defun cache-tag (path)
  "Cache partition.  Public responses share one entry.  Keyed responses
are partitioned by a short hash of the key, not the key itself."
  (cond ((public-path-p path) "public")
        ((usable-key-p *api-key*)
         (ironclad:byte-array-to-hex-string
          (subseq (ironclad:digest-sequence
                   :sha256
                   (babel:string-to-octets *api-key* :encoding :utf-8))
                  0 8)))
        (t "none")))

(defun make-request-uri (path query-args)
  (quri:make-uri :defaults (concatenate 'string *api* path)
                 :query (query-alist query-args)))

(defun http-get (path &key (query-args '()))
  "HTTP GET of PATH on *API*.  Returns the body and the request URI.
Redirects are not followed, so the key cannot be sent to another host.
429 RATE_LIMITED is retried.  MONTHLY_LIMIT and other statuses signal
an API-ERROR subclass."
  (require-key path)
  (let ((uri (make-request-uri path query-args))
        (attempts (max 1 *max-retries*)))
    (values
     (loop for attempt from 1 to attempts
           do (handler-case
                  (return (dex:get uri
                                   :headers (request-headers)
                                   :bearer-auth (when (send-key-p path) *api-key*)
                                   :max-redirects 0
                                   :connect-timeout *request-timeout-seconds*
                                   :read-timeout *request-timeout-seconds*))
                (error (condition)
                  (let ((status (http-status condition)))
                    (cond ((null status)
                           (error condition))
                          (t
                           (let* ((body (http-body condition))
                                  (code (nth-value 0 (error-fields body))))
                             (if (and (eq (classify-error status code) 'rate-limited)
                                      (< attempt attempts))
                                 (sleep (or (retry-after-seconds condition)
                                            (* *retry-wait-seconds* attempt)))
                                 (error (api-error-from status body uri))))))))))
     uri)))

(defun parse-response (body uri)
  (let* ((text (ensure-text body))
         (url (uri-string uri))
         (payload (handler-case (parse-json-text text)
                    (error ()
                      (error 'api-error
                             :url url
                             :error-message "Response was not JSON."
                             :body text)))))
    (when (api-refusal-p payload)
      (error (api-error-from 200 text url)))
    payload))

(defun http-get-json (path &key (query-args '()))
  "GET PATH and parse JSON.  Arrays become vectors; booleans become symbols.
A success:false body is an API-ERROR even when HTTP status was 200."
  (multiple-value-bind (body uri) (http-get path :query-args query-args)
    (parse-response body uri)))

(function-cache:defcached
    (http-get-json-cached :timeout *api-cache-timeout-seconds*)
    (path query-args cache-tag)
  (declare (ignore cache-tag))
  (http-get-json path :query-args query-args))

(sigma/control:function-alias 'http-get-json 'http-get-json-do-not-cache)

(defun api-get (path &key query (cache t))
  "GET PATH with QUERY pairs.  CACHE uses the 60-second layer, partitioned
so one key's response is not reused for another."
  (if cache
      (http-get-json-cached path query (cache-tag path))
      (http-get-json path :query-args query)))

(behavior 'cache-tag
  (let ((*api-key* "pidx_abc"))
    (should-string= "public" (cache-tag "/api/index/v1/pubkey"))
    (should-be-true (stringp (cache-tag "/api/index/v1/price")))
    (should-not-string= "public" (cache-tag "/api/index/v1/price"))
    (should-not-string= "pidx_abc" (cache-tag "/api/index/v1/price")))
  (let ((*api-key* nil))
    (should-string= "none" (cache-tag "/api/index/v1/price"))))

(behavior 'api-uri
  (should-string= "https://mcp.thepulse.markets/api/index/v1/price?symbol=BTC"
                  (api-uri "/api/index/v1/price" "symbol" "BTC" "missing" nil)))

;;;; -- Endpoints -------------------------------------------------------------
;; Names are the documented REST paths.  Keyword arguments are the query
;; parameters.  Live prices default to an uncached read: a 60-second cache
;; would serve a stale signed print.  Reference reads default to cached.
;;
;; Customer /price and /batch rows are signed.  /verity/price and
;; /verity/batch are the unsigned breadth read.  /history dataset=verified
;; is the signed archive (Builder and above).  dataset=reconstructed is
;; candles rebuilt from older source observations and is not a contemporaneous
;; signature.  WebSocket /api/index/v1/stream is not wrapped.

(defun get-health (&key (cache nil))
  "GET /api/index/v1/health
200 while the index meets its quality floors, 503 when degraded.  Public."
  (api-get (v1 "health") :cache cache))

(defun fetch-pubkey ()
  (api-get (v1 "pubkey") :cache nil))

(function-cache:defcached
    (get-pubkey-cached :timeout *pubkey-cache-timeout-seconds*)
    ()
  (fetch-pubkey))

(defun get-pubkey (&key (cache t))
  "GET /api/index/v1/pubkey
Verification-key ring, algorithm, and the v1/v2 canonical recipes.  Public.
Cached for *PUBKEY-CACHE-TIMEOUT-SECONDS* (default 300).  No key is sent."
  (if cache
      (get-pubkey-cached)
      (fetch-pubkey)))

(defun get-status (&key (cache t))
  "GET /api/index/v1/status
Aggregate uptime, connected sources, and newest-print age.  Public.
Venue identities are not in this payload."
  (api-get (v1 "status") :cache cache))

(defun get-symbols (&key (cache t))
  "GET /api/index/v1/symbols
The served ticker universe.  Public."
  (api-get (v1 "symbols") :cache cache))

(defun get-uptime (&key (cache nil))
  "GET /api/index/v1/uptime
External uptime probe summary.  Public."
  (api-get (v1 "uptime") :cache cache))

(defun get-terms (&key (cache t))
  "GET /api/index/v1/terms
The data terms that govern the API.  Public."
  (api-get (v1 "terms") :cache cache))

(defun get-incidents (&key (cache t))
  "GET /api/index/v1/incidents
Published incident notes.  Public."
  (api-get (v1 "incidents") :cache cache))

(defun get-speed (&key (cache nil))
  "GET /api/index/v1/speed
Publish-rate counters.  Public."
  (api-get (v1 "speed") :cache cache))

(defun get-sample (symbol &key (cache nil))
  "GET /api/index/v1/sample?symbol=BTC
Keyless signed print.  Only BTC, ETH, and SOL are served here.
The payload is the same signed shape as GET-PRICE, plus sample:true."
  (let ((ticker (canonicalize-symbol symbol)))
    (unless ticker (error "A symbol is required."))
    (unless (sample-symbol-p ticker)
      (error "The sample endpoint only covers BTC, ETH, and SOL."))
    (api-get (v1 "sample")
             :query (query "symbol" ticker)
             :cache cache)))

(defun get-price (symbol &key (cache nil))
  "GET /api/index/v1/price?symbol=BTC
Current signed print.  Requires a key.  The v1 signature covers symbol,
priceText, at, and grade.  The v2 block, when present, signs the wider
record; quality and cadence fields are outside the v1 signature.
An unsupported symbol is UNSUPPORTED-SYMBOL, not a price of zero."
  (let ((ticker (canonicalize-symbol symbol)))
    (unless ticker (error "A symbol is required."))
    (api-get (v1 "price")
             :query (query "symbol" ticker)
             :cache cache)))

(defun get-batch (symbols &key (cache nil))
  "GET /api/index/v1/batch?symbols=BTC,ETH
Up to 100 symbols.  Each successful row is signed on its own.
An unsupported symbol is a row with success:false, not a failed request.
Requires a key.  The plan may allow fewer than 100."
  (let ((tickers (canonicalize-symbols symbols)))
    (unless tickers (error "At least one symbol is required."))
    (api-get (v1 "batch")
             :query (query "symbols" tickers)
             :cache cache)))

(defun get-print (symbol at &key (cache nil))
  "GET /api/index/v1/print?symbol=BTC&at=<ISO or epoch-ms>
The signed print nearest AT, plus deltaMs.  AT is an ISO-8601 string,
universal time, UNIX seconds, or UNIX milliseconds.  Requires a key.
deltaMs is not signed.  The print is the nearest recorded sample, not
a price synthesized at that instant."
  (let ((ticker (canonicalize-symbol symbol)))
    (unless ticker (error "A symbol is required."))
    (let ((moment (canonicalize-time at)))
      (unless moment (error "AT is required."))
      (api-get (v1 "print")
               :query (query "symbol" ticker "at" moment)
               :cache cache))))

(defun get-metadata (symbols &key (cache t))
  "GET /api/index/v1/metadata?symbols=BTC,ETH
Curated identity fields.  Requires a key."
  (let ((tickers (canonicalize-symbols symbols)))
    (unless tickers (error "At least one symbol is required."))
    (api-get (v1 "metadata")
             :query (query "symbols" tickers)
             :cache cache)))

(defun get-history (symbol &key (dataset :verified) (interval "1m")
                           from to limit cursor (cache nil))
  "GET /api/index/v1/history
Candles and the observations behind them.
DATASET is verified (signed archive) or reconstructed (not a
contemporaneous signature).  INTERVAL is 1m, 5m, 1h, or 1d.
FROM and TO are ISO-8601, universal times, or UNIX times.
LIMIT is a page size.  CURSOR is pagination.nextCursor from the previous page.
Without FROM/TO the service walks from the start of the archive.
Builder plan and above.  Pass FORMAT only by calling the URL yourself;
this wrapper asks for JSON."
  (let ((ticker (canonicalize-symbol symbol)))
    (unless ticker (error "A symbol is required."))
    (api-get (v1 "history")
             :query (query "symbol" ticker
                           "dataset" (canonicalize-dataset dataset)
                           "interval" (canonicalize-interval interval)
                           "from" (canonicalize-time from)
                           "to" (canonicalize-time to)
                           "limit" limit
                           "cursor" cursor)
             :cache cache)))

(defun get-research-compare (symbols &key (dataset :reconstructed) (interval "1d")
                                     from to (cache nil))
  "GET /api/index/v1/research/compare?symbols=BTC,ETH
Returns, volatility, drawdown, and correlation.  Builder plan and above.
DATASET defaults to reconstructed, matching the published example."
  (let ((tickers (canonicalize-symbols symbols)))
    (unless tickers (error "At least one symbol is required."))
    (api-get (v1 "research/compare")
             :query (query "symbols" tickers
                           "dataset" (canonicalize-dataset dataset)
                           "interval" (canonicalize-interval interval)
                           "from" (canonicalize-time from)
                           "to" (canonicalize-time to))
             :cache cache)))

(defun get-source-health (&key (cache nil))
  "GET /api/index/v1/source-health
Aggregate source-panel health.  No venue identities or weights.
Commercial and Enterprise."
  (api-get (v1 "source-health") :cache cache))

(defun get-verity-price (symbol &key (cache nil))
  "GET /api/index/v1/verity/price?symbol=BTC
Unsigned breadth read: tier, sources, confidence, dispersion, interval,
and cadence.  Not a signed print.  Requires a key."
  (let ((ticker (canonicalize-symbol symbol)))
    (unless ticker (error "A symbol is required."))
    (api-get (v1 "verity/price")
             :query (query "symbol" ticker)
             :cache cache)))

(defun get-verity-batch (symbols &key (cache nil))
  "GET /api/index/v1/verity/batch?symbols=BTC,ETH
Up to 200 unsigned Verity rows.  A symbol without a publishable price
is isolated to its row (ok:false).  Requires a key."
  (let ((tickers (canonicalize-symbols symbols)))
    (unless tickers (error "At least one symbol is required."))
    (api-get (v1 "verity/batch")
             :query (query "symbols" tickers)
             :cache cache)))

(defun get-verity-catalog (&key band status limit offset (cache t))
  "GET /api/index/v1/verity/catalog
One page of observed assets, priced or not.  Rows are unsigned.
BAND is real-time, five-second, ten-second, slow, or unavailable.
STATUS is consensus, blended, indicative, insufficient-coverage,
venue-disagreement, unconvertible-quote, stale, or kernel-rejected.
LIMIT 1..100 and OFFSET are the page.  Requires a key."
  (api-get (v1 "verity/catalog")
           :query (query "band" band
                         "status" status
                         "limit" limit
                         "offset" offset)
           :cache cache))

(defun get-verity-venues (&key (cache t))
  "GET /api/index/v1/verity/venues
Panel counts and the disclosure.  Per-venue rows are not published.  Public."
  (api-get (v1 "verity/venues") :cache cache))

(defun get-verity-status (&key (cache t))
  "GET /api/index/v1/verity/status
Counts: venues, markets, assets by tier, cadence bands.  Public."
  (api-get (v1 "verity/status") :cache cache))

(behavior 'local-configuration-path
  (should-string= "local-configuration" (pathname-name (local-configuration-path)))
  (should-string= "lisp" (pathname-type (local-configuration-path)))
  (should-be-true (search "configuration" (namestring (local-configuration-path)))))

(behavior 'configure-from-environment
  (let ((*api-key* "pidx_fromfile"))
    (configure-from-environment)
    (should-string= "pidx_fromfile" *api-key*))
  (let ((*api-key* nil))
    (let ((from-env (or (uiop:getenv "PULSE_API_KEY")
                        (uiop:getenv "THEPULSE_MARKETS_API_KEY"))))
      (configure-from-environment)
      (if (usable-key-p from-env)
          (should-string= from-env *api-key*)
          (should-be-null *api-key*)))))

(reload-local-configuration)
(configure-from-environment)
