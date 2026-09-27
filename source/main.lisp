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

(uiop:define-package #:thepulse-markets
  (:use #:common-lisp #:sigma/behave #:thepulse-markets/rest-api)
  (:reexport #:thepulse-markets/rest-api)
  (:export #:price
           #:prices
           #:btc
           #:eth
           #:sol
           #:verity-price
           #:settlement-print
           #:print-price
           #:parse-price
           #:canonical-v1
           #:canonical-v2
           #:verify-print
           #:*history-max-pages*
           #:price-history
           #:ohlc-history
           #:ohlc-bar
           #:ohlc-bar-p
           #:ohlc-bar-time
           #:ohlc-bar-open
           #:ohlc-bar-high
           #:ohlc-bar-low
           #:ohlc-bar-close
           #:ohlc-bar-volume
           #:ohlc-bar-adjusted-close
           #:make-ohlc-bar
           #:ohlc-bar-tuple
           #:ohlc-bars-for-ingest
           #:load-fixture
           #:version-string
           #:version-list
           #:version-major
           #:version-minor
           #:version-revision)
  (:import-from #:thepulse-markets/system
                #:version-string
                #:version-list
                #:version-major
                #:version-minor
                #:version-revision))
(in-package #:thepulse-markets)

(defvar *history-max-pages* 20
  "Page cap when OHLC-HISTORY and PRICE-HISTORY follow cursors.
History pages about 2000 observations.  Twenty pages covers a day of
1-minute verified history with room to spare.")

(defvar *index-sig-v1* "pulse-index-v1")
(defvar *index-sig-v2* "pulse-index-v2")

(defun load-fixture (name)
  "Parse a JSON file under test-fixtures/.  Used by the load-time specs."
  (let ((path (asdf:system-relative-pathname
               :thepulse-markets
               (merge-pathnames name #p"test-fixtures/")))
        (yason:*parse-json-arrays-as-vectors* t)
        (yason:*parse-json-booleans-as-symbols* t))
    (with-open-file (in path)
      (yason:parse in))))

(defun parse-price (value)
  "A Pulse price field as a number.  Strings are read as double-floats
so they match Yason's JSON numbers.  NIL when VALUE is not a price."
  (cond ((numberp value) value)
        ((and (stringp value) (plusp (length value)))
         (let ((*read-default-float-format* 'double-float))
           (handler-case
               (let ((number (read-from-string value)))
                 (when (realp number) number))
             (error () nil))))
        (t nil)))

(defun print-price (print)
  "The number on a signed print or Verity row.
priceText wins over price.  NIL when the row has no price
(an unsupported symbol is not zero)."
  (when (hash-table-p print)
    (or (parse-price (gethash "priceText" print))
        (parse-price (gethash "price" print)))))

(defun prices-agree-p (left right)
  (let ((a (parse-price left))
        (b (parse-price right)))
    (and (numberp a) (numberp b) (= a b))))

(defun signed-price-text (print)
  "The price characters that go into the v1 canonical string.
priceText when the API sent it, else a string price, else a printed number.
Reprinting a float is a fallback; prefer priceText."
  (let ((price-text (gethash "priceText" print))
        (price (gethash "price" print)))
    (cond ((stringp price-text) price-text)
          ((stringp price) price)
          ((numberp price)
           (let ((*read-default-float-format* 'double-float))
             (format nil "~A" price)))
          (t nil))))

(defun price-text-disagrees-p (print)
  (let ((price-text (gethash "priceText" print))
        (price (gethash "price" print)))
    (and (stringp price-text)
         price
         (not (prices-agree-p price-text price)))))

(defun canonical-v1 (print)
  "The v1 signed string: pulse-index-v1, symbol, price text, at, grade,
separated by newlines.  NIL when a field is missing.
This covers only those four fields.  Tier, confidence, cadence, kid,
and deltaMs are not in it."
  (when (hash-table-p print)
    (let ((symbol (gethash "symbol" print))
          (at (gethash "at" print))
          (grade (gethash "grade" print))
          (text (signed-price-text print)))
      (when (and (stringp symbol) (plusp (length symbol))
                 (stringp at) (plusp (length at))
                 (stringp grade) (plusp (length grade))
                 (stringp text) (plusp (length text)))
        (format nil "~A~%~A~%~A~%~A~%~A"
                *index-sig-v1* symbol text at grade)))))

(defun canonical-v2 (print)
  "The canonical string Pulse attached under v2, or NIL.
That string is what the v2 signature covers.  Do not rebuild it."
  (let ((v2 (and (hash-table-p print) (gethash "v2" print))))
    (when (and (hash-table-p v2) (stringp (gethash "canonical" v2)))
      (gethash "canonical" v2))))

(behavior 'parse-price
  (should= 100.5d0 (parse-price "100.5"))
  (should= 100.5d0 (parse-price 100.5d0))
  (should-be-null (parse-price nil))
  (should-be-null (parse-price "nope")))

;;;; -- Signature verification ------------------------------------------------
;; ECDSA P-256 / SHA-256, IEEE-P1363 r||s, standard base64.
;; Ironclad's P-256 verify does not hash; the SHA-256 digest is the message.
;; The public key is the uncompressed point from the JWK (or the PEM tail).

(defun base64url->octets (text)
  (let* ((standard (substitute #\+ #\- (substitute #\/ #\_ text)))
         (remainder (mod (length standard) 4))
         (padded (if (zerop remainder)
                     standard
                     (concatenate 'string standard
                                  (make-string (- 4 remainder)
                                               :initial-element #\=)))))
    (cl-base64:base64-string-to-usb8-array padded)))

(defun octets (sequence)
  (coerce sequence '(simple-array (unsigned-byte 8) (*))))

(defun jwk->point (jwk)
  (unless (and (hash-table-p jwk)
               (string= "P-256" (or (gethash "crv" jwk) "")))
    (error "Pulse verification key is not P-256."))
  (let ((x (base64url->octets (gethash "x" jwk)))
        (y (base64url->octets (gethash "y" jwk))))
    (unless (and (= 32 (length x)) (= 32 (length y)))
      (error "Pulse P-256 coordinates are not 32 bytes."))
    (octets (concatenate '(vector (unsigned-byte 8)) #(4) x y))))

(defun pem-body (pem)
  (with-output-to-string (out)
    (dolist (line (uiop:split-string pem :separator '(#\Newline #\Return)))
      (let ((trimmed (string-trim '(#\Space #\Tab) line)))
        (unless (or (zerop (length trimmed))
                    (search "-----" trimmed))
          (write-string trimmed out))))))

(defun pem->point (pem)
  (let ((der (cl-base64:base64-string-to-usb8-array (pem-body pem))))
    (unless (>= (length der) 65)
      (error "Pulse public key PEM is too short."))
    (let ((point (subseq der (- (length der) 65))))
      (unless (= (aref point 0) 4)
        (error "Pulse public key is not an uncompressed P-256 point."))
      (octets point))))

(defun p256-public-key (jwk pem)
  (ironclad:make-public-key
   :secp256r1
   :y (cond ((hash-table-p jwk) (jwk->point jwk))
            ((and (stringp pem) (plusp (length pem))) (pem->point pem))
            (t (error "Pulse verification key has no JWK or PEM.")))))

(defun parse-key-ring (document)
  "Hash table of kid -> P-256 public key, built from a /pubkey payload.
At most 16 keys.  A document with only publicKeyPem is stored under
activeKid, or under the empty string when no kid is published."
  (unless (hash-table-p document)
    (error "Pulse key ring is not a JSON object."))
  (let ((table (make-hash-table :test #'equal))
        (count 0))
    (dolist (entry (json-list (gethash "verificationKeys" document)))
      (when (hash-table-p entry)
        (incf count)
        (when (> count 16)
          (error "Pulse key ring has more than 16 keys."))
        (let ((kid (or (gethash "kid" entry) "")))
          (when (gethash kid table)
            (error "Duplicate Pulse verification key id ~A." kid))
          (setf (gethash kid table)
                (p256-public-key (gethash "jwk" entry) (gethash "pem" entry))))))
    (when (zerop (hash-table-count table))
      (let ((pem (gethash "publicKeyPem" document))
            (jwk (gethash "publicKeyJwk" document)))
        (when (or (stringp pem) (hash-table-p jwk))
          (setf (gethash (or (gethash "activeKid" document) "") table)
                (p256-public-key jwk pem)))))
    (when (zerop (hash-table-count table))
      (error "Pulse key ring has no verification key."))
    table))

(defun ensure-key-ring (key-ring)
  (cond ((null key-ring)
         (parse-key-ring (get-pubkey)))
        ((and (hash-table-p key-ring)
              (or (gethash "verificationKeys" key-ring)
                  (gethash "publicKeyPem" key-ring)
                  (gethash "publicKeyJwk" key-ring)))
         (parse-key-ring key-ring))
        ((hash-table-p key-ring) key-ring)
        (t (error "KEY-RING must be a /pubkey document or a kid table."))))

(defun decode-signature (signature)
  (when (stringp signature)
    (handler-case
        (let ((octets (cl-base64:base64-string-to-usb8-array signature)))
          (when (= (length octets) 64)
            (octets octets)))
      (error () nil))))

(defun verify-p256 (public-key message signature)
  "True when SIGNATURE is the P-256 SHA-256 signature of MESSAGE.
MESSAGE and SIGNATURE are octet vectors.  A bad signature is NIL, not an error."
  (handler-case
      (let ((digest (ironclad:digest-sequence :sha256 message)))
        (and (= 32 (length digest))
             (= 64 (length signature))
             (ironclad:verify-signature public-key digest signature)))
    (error () nil)))

(defun candidate-keys (ring kid)
  "Pairs (kid . key).  A kid selects that key only.  No kid tries the ring."
  (if (and (stringp kid) (plusp (length kid)))
      (let ((key (gethash kid ring)))
        (when key (list (cons kid key))))
      (loop for id being the hash-keys of ring
            using (hash-value key)
            collect (cons id key))))

(defun verify-message (ring kid message signature-b64)
  "Values: verified-p and the kid that verified, or NIL NIL."
  (let ((signature (decode-signature signature-b64))
        (bytes (and (stringp message)
                    (babel:string-to-octets message :encoding :utf-8))))
    (unless (and signature bytes)
      (return-from verify-message (values nil nil)))
    (loop for (id . key) in (candidate-keys ring kid)
          when (verify-p256 key bytes signature)
            return (values t id)
          finally (return (values nil nil)))))

(defun verify-print-against (print ring version)
  (when (price-text-disagrees-p print)
    (return-from verify-print-against
      (list :valid nil :reason :price-text-mismatch :v1 nil :v2 nil)))
  (let* ((want-v1 (member version '(:v1 :both)))
         (want-v2 (member version '(:v2 :both)))
         (v2 (gethash "v2" print))
         (v2doc (when (hash-table-p v2) v2))
         (checked nil)
         (v1 nil)
         (v1-kid nil)
         (v2-ok nil)
         (v2-kid nil)
         (reason nil))
    (when want-v1
      (setf checked (canonical-v1 print))
      (if checked
          (multiple-value-bind (ok kid)
              (verify-message ring (gethash "kid" print) checked
                              (gethash "signature" print))
            (setf v1 ok
                  v1-kid kid))
          (setf reason :incomplete)))
    (when want-v2
      (let ((canonical (and v2doc (gethash "canonical" v2doc))))
        (cond ((not (stringp canonical))
               (unless reason (setf reason :no-v2)))
              (t
               (unless checked (setf checked canonical))
               (multiple-value-bind (ok kid)
                   (verify-message ring
                                   (or (gethash "kid" v2doc)
                                       (gethash "kid" print))
                                   canonical
                                   (gethash "signature" v2doc))
                 (setf v2-ok ok
                       v2-kid kid))))))
    (let ((valid (and (or (not want-v1) v1)
                      (or (not want-v2)
                          (and (null v2doc) (eq version :both) v1)
                          v2-ok))))
      (list :valid (and valid t)
            :v1 v1
            :v2 v2-ok
            :kid (or v1-kid v2-kid)
            :checked checked
            :reason (cond (valid nil)
                          (reason reason)
                          (t :bad-signature))))))

(defun verify-print (print &key key-ring (version :v1))
  "T when PRINT's signature matches the Pulse key ring.
The second value is a plist: :valid :v1 :v2 :kid :checked :reason.
VERSION is :V1 (default), :V2, or :BOTH.  :BOTH accepts a print that
has no v2 block.  When v2 is present, :BOTH requires that signature too.
KEY-RING is a /pubkey document or a kid -> public-key table.  With none,
the ring is fetched and, if the signature does not verify, fetched once
more with the cache bypassed.  A KEY-RING you pass is not refreshed.
:REASON :price-text-mismatch means price and priceText are different
numbers, so the print was not checked.  valid T does not cover kid,
tier, confidence, cadence, or deltaMs unless VERSION includes :V2,
and even then only the fields inside the v2 canonical string."
  (unless (member version '(:v1 :v2 :both))
    (error "VERSION must be :V1, :V2, or :BOTH."))
  (unless (hash-table-p print)
    (return-from verify-print
      (values nil (list :valid nil :reason :not-a-print))))
  (let ((report (verify-print-against print (ensure-key-ring key-ring) version)))
    (when (and (not (getf report :valid))
               (null key-ring)
               (not (member (getf report :reason)
                            '(:price-text-mismatch :incomplete :no-v2 :not-a-print))))
      (setf report (verify-print-against print
                                         (ensure-key-ring (get-pubkey :cache nil))
                                         version)))
    (values (getf report :valid) report)))

(defun copy-table (table)
  (let ((copy (make-hash-table :test #'equal)))
    (maphash (lambda (key value) (setf (gethash key copy) value)) table)
    copy))

(behavior 'verify-print
  (let* ((print (load-fixture "price-btc.json"))
         (ring (load-fixture "pubkey.json"))
         (checked (canonical-v1 print)))
    (should-be-true (stringp checked))
    (should-string= *index-sig-v1* (subseq checked 0 (length *index-sig-v1*)))
    (should-be-true (search (gethash "priceText" print) checked))
    (should-be-true (verify-print print :key-ring ring))
    (should-be-true (verify-print print :key-ring ring :version :v2))
    (should-be-true (verify-print print :key-ring ring :version :both))
    (let ((tampered (copy-table print)))
      (setf (gethash "priceText" tampered) "1")
      (should-be-false (verify-print tampered :key-ring ring)))
    (let ((tampered (copy-table print)))
      (setf (gethash "grade" tampered) "indicative")
      (should-be-false (verify-print tampered :key-ring ring)))
    (let* ((tampered (copy-table print))
           (v2 (copy-table (gethash "v2" tampered))))
      (setf (gethash "v2" tampered) v2)
      (setf (gethash "canonical" v2) "pulse-index-v2~%tampered")
      (should-be-true (verify-print tampered :key-ring ring :version :v1))
      (should-be-false (verify-print tampered :key-ring ring :version :v2)))
    (let ((tampered (copy-table print)))
      (setf (gethash "price" tampered) 1)
      (should-be-false (verify-print tampered :key-ring ring))
      (let ((report (nth-value 1 (verify-print tampered :key-ring ring))))
        (should-eq :price-text-mismatch (getf report :reason))))))

;;;; -- Current prices --------------------------------------------------------

(defun price (symbol &key (cache nil))
  "Current index price of SYMBOL as a number.
The second value is the signed print (the hash from /price, or from
/sample when no usable key is set and SYMBOL is BTC, ETH, or SOL).
An unsupported symbol signals UNSUPPORTED-SYMBOL.  It is not zero.
CACHE defaults to NIL so a signed print is not reused for 60 seconds."
  (let ((ticker (canonicalize-symbol symbol)))
    (unless ticker (error "A symbol is required."))
    (let ((print (if (and (not (usable-key-p *api-key*))
                          (sample-symbol-p ticker))
                     (get-sample ticker :cache cache)
                     (get-price ticker :cache cache))))
      (values (print-price print) print))))

(defun row-ok-p (row)
  (or (json-true-p (gethash "success" row))
      (json-true-p (gethash "ok" row))))

(defun batch-rows (payload)
  (mapcar (lambda (row)
            (list :symbol (gethash "symbol" row)
                  :price (when (row-ok-p row) (print-price row))
                  :print (when (gethash "signature" row) row)
                  :code (gethash "code" row)
                  :message (gethash "message" row)))
          (json-list (or (gethash "observations" payload)
                         (gethash "rows" payload)))))

(defun prices (symbols &key (cache nil))
  "One plist per symbol: :symbol :price :print :code :message.
A key uses one /batch call.  Without a key, every symbol must be
BTC, ETH, or SOL and each is read from the sample.  A bad ticker is
a row with :price NIL and a :code, not a failed batch, when a key is set."
  (let ((tickers (canonicalize-symbols symbols)))
    (unless tickers (error "At least one symbol is required."))
    (cond ((usable-key-p *api-key*)
           (batch-rows (get-batch tickers :cache cache)))
          ((every #'sample-symbol-p tickers)
           (mapcar (lambda (ticker)
                     (let ((print (get-sample ticker :cache cache)))
                       (list :symbol ticker
                             :price (print-price print)
                             :print print
                             :code nil
                             :message nil)))
                   tickers))
          (t
           (error 'needs-key
                  :url (api-uri "/api/index/v1/batch" "symbols" tickers)
                  :error-message
                  "Batch reads need a Pulse developer key. Without one, PRICES only accepts BTC, ETH, and SOL.")))))

(defun btc ()
  "Keyless-capable Bitcoin index price.  Same values as (PRICE :BTC)."
  (price "BTC"))

(defun eth ()
  "Keyless-capable Ethereum index price."
  (price "ETH"))

(defun sol ()
  "Keyless-capable Solana index price."
  (price "SOL"))

(defun verity-price (symbol &key (cache nil))
  "Unsigned Verity breadth price.  Second value is the raw row.
This is not a signed print; VERIFY-PRINT does not apply to it."
  (let ((row (get-verity-price symbol :cache cache)))
    (values (print-price row) row)))

(defun settlement-print (symbol at &key (cache nil))
  "Signed print nearest AT.  Values are price, the print, and deltaMs.
AT is ISO-8601, universal time, UNIX seconds, or UNIX milliseconds.
deltaMs is how far the recorded print sits from AT.  It is not signed."
  (let ((print (get-print symbol at :cache cache)))
    (values (print-price print) print (gethash "deltaMs" print))))

;;;; -- OHLC bars -------------------------------------------------------------

(defclass ohlc-bar ()
  ((time
    :initarg :time
    :accessor ohlc-bar-time
    :documentation "Universal time of the bar open.  Fractional seconds are truncated.")
   (open
    :initarg :open
    :accessor ohlc-bar-open)
   (high
    :initarg :high
    :accessor ohlc-bar-high)
   (low
    :initarg :low
    :accessor ohlc-bar-low)
   (close
    :initarg :close
    :accessor ohlc-bar-close)
   (volume
    :initarg :volume
    :accessor ohlc-bar-volume
    :initform nil
    :documentation "NIL.  Pulse history has an observation count, not trade volume.
The count stays on the raw GET-HISTORY payload.")
   (adjusted-close
    :initarg :adjusted-close
    :accessor ohlc-bar-adjusted-close
    :initform nil
    :documentation "NIL.  The index close is the close."))
  (:documentation
   "One Pulse index bar.  This is not a CANDLESTICKS:CANDLESTICK.
Use OHLC-BARS-FOR-INGEST to feed candlesticks.  Quote currency is USD."))

(defun ohlc-bar-p (object)
  (typep object 'ohlc-bar))

(defun make-ohlc-bar (&key time open high low close volume adjusted-close)
  (make-instance 'ohlc-bar
                 :time time
                 :open open
                 :high high
                 :low low
                 :close close
                 :volume volume
                 :adjusted-close adjusted-close))

(defmethod print-object ((bar ohlc-bar) stream)
  (print-unreadable-object (bar stream :type t)
    (format stream "@ ~A: o~A h~A l~A c~A"
            (ohlc-bar-time bar)
            (ohlc-bar-open bar)
            (ohlc-bar-high bar)
            (ohlc-bar-low bar)
            (ohlc-bar-close bar))))

(defun ohlc-bar-tuple (bar)
  "One ingest row for CANDLESTICKS:INGEST-CANDLESTICKS:
   (time open high low close volume adjusted-close)."
  (list (ohlc-bar-time bar)
        (ohlc-bar-open bar)
        (ohlc-bar-high bar)
        (ohlc-bar-low bar)
        (ohlc-bar-close bar)
        (ohlc-bar-volume bar)
        (ohlc-bar-adjusted-close bar)))

(defun ohlc-bars-for-ingest (bars)
  "Translate OHLC-BARs into the list CANDLESTICKS:INGEST-CANDLESTICKS expects.
Volume is NIL.  Do not read it as share volume."
  (map 'list #'ohlc-bar-tuple bars))

(defun interval-seconds (interval)
  (cdr (assoc interval
              '(("1m" . 60) ("5m" . 300) ("1h" . 3600) ("1d" . 86400))
              :test #'string=)))

(defun bucket-universal (universal interval)
  "Open of the UTC bucket containing UNIVERSAL, for a Pulse interval."
  (let ((step (interval-seconds interval)))
    (if step
        (unix->universal (* step (floor (universal->unix universal) step)))
        universal)))

(defun group->bar (time points)
  "POINTS are (universal-time price) in chronological order."
  (let ((prices (mapcar #'second points)))
    (make-ohlc-bar :time time
                   :open (second (first points))
                   :high (reduce #'max prices)
                   :low (reduce #'min prices)
                   :close (second (car (last points))))))

(defun observations->bars (observations interval)
  "OHLC bars from signed history observations.
Each observation's price is the index at that timestamp.  Bars follow
INTERVAL (1m, 5m, 1h, 1d) in UTC."
  (let ((rows (sort (copy-list (json-list observations))
                    #'string<
                    :key (lambda (row) (or (gethash "at" row) "")))))
    (loop with groups = nil
          with current-time = nil
          with current = nil
          for row in rows
          for at = (parse-iso-8601 (gethash "at" row))
          for price = (parse-price (or (gethash "priceText" row)
                                       (gethash "price" row)))
          when (and at price)
            do (let ((bucket (bucket-universal at interval)))
                 (cond ((and current-time (= bucket current-time))
                        (push (list at price) current))
                       (t
                        (when current
                          (push (cons current-time (nreverse current)) groups))
                        (setf current-time bucket
                              current (list (list at price))))))
          finally
             (when current
               (push (cons current-time (nreverse current)) groups))
             (return (nreverse
                      (mapcar (lambda (group)
                                (group->bar (car group) (cdr group)))
                              groups))))))

(defun fragments->bar (parts)
  "Merge page-local candles that share a timestamp.
Open is the first fragment, close the last, high the max, low the min.
That is the full bar when the fragments partition the bucket in order."
  (make-ohlc-bar :time (parse-iso-8601 (gethash "at" (first parts)))
                 :open (gethash "open" (first parts))
                 :high (reduce #'max parts :key (lambda (candle) (gethash "high" candle)))
                 :low (reduce #'min parts :key (lambda (candle) (gethash "low" candle)))
                 :close (gethash "close" (car (last parts)))))

(defun merge-candles (candles)
  (let ((groups nil))
    (dolist (candle (json-list candles))
      (let* ((at (gethash "at" candle))
             (found (and (stringp at) (assoc at groups :test #'string=))))
        (cond ((null at) nil)
              (found (push candle (cdr found)))
              (t (push (list at candle) groups)))))
    (loop for group in (nreverse groups)
          for parts = (nreverse (cdr group))
          for bar = (fragments->bar parts)
          when (ohlc-bar-time bar)
            collect bar)))

(defun page-observations (pages)
  (loop for page in pages
        append (json-list (gethash "verifiedObservations" page))))

(defun history-bars (pages interval)
  "Bars from signed observations when the pages have them.
Reconstructed pages have candles and no observations; those candles
are merged across pages."
  (let ((observations (page-observations pages)))
    (if observations
        (observations->bars observations interval)
        (merge-candles (loop for page in pages
                             append (json-list (gethash "candles" page)))))))

(defun history-points (pages interval)
  " (universal-time price) pairs.  Verified pages use each observation.
Reconstructed pages use each bar's close.  Universal time drops
the fractional second; the raw at string is on the GET-HISTORY payload."
  (let ((observations (page-observations pages)))
    (if observations
        (loop for row in (sort (copy-list observations) #'string<
                               :key (lambda (row) (or (gethash "at" row) "")))
              for at = (parse-iso-8601 (gethash "at" row))
              for price = (parse-price (or (gethash "priceText" row)
                                           (gethash "price" row)))
              when (and at price)
                collect (list at price))
        (mapcar (lambda (bar)
                  (list (ohlc-bar-time bar) (ohlc-bar-close bar)))
                (history-bars pages interval)))))

(defun time->universal (value)
  (etypecase value
    (string (or (parse-iso-8601 value)
                (error "Cannot parse time ~S." value)))
    (integer (or (parse-iso-8601 (canonicalize-time value))
                 (error "Cannot parse time ~S." value)))))

(defun history-bounds (from to)
  "Two ISO-8601 strings.  Missing TO is now.  Missing FROM is 24 hours before TO.
When both are supplied they are canonicalized and no default is applied."
  (if (and from to)
      (values (canonicalize-time from) (canonicalize-time to))
      (let* ((end (if to (time->universal to) (get-universal-time)))
             (start (if from (time->universal from) (- end (* 24 60 60)))))
        (values (format-iso-8601 start) (format-iso-8601 end)))))

(defun collect-history-pages (symbol &key dataset interval from to limit follow max-pages cache)
  (if (not follow)
      (list (get-history symbol :dataset dataset :interval interval
                         :from from :to to :limit limit :cache cache))
      (let ((pages nil)
            (cursor nil)
            (seen (make-hash-table :test #'equal)))
        (loop for n from 1 to (max 1 max-pages)
              for page = (get-history symbol :dataset dataset :interval interval
                                      :from from :to to :limit limit
                                      :cursor cursor :cache cache)
              do (push page pages)
                 (let ((next (json-ref page "pagination" "nextCursor")))
                   (unless (and (json-true-p (json-ref page "pagination" "truncated"))
                                (stringp next)
                                (plusp (length next))
                                (not (gethash next seen)))
                     (return))
                   (setf (gethash next seen) t
                         cursor next)))
        (nreverse pages))))

(defun history-truncated-p (pages max-pages followed)
  (let* ((last (car (last pages)))
         (next (json-ref last "pagination" "nextCursor")))
    (and (json-true-p (json-ref last "pagination" "truncated"))
         (or (not followed)
             (>= (length pages) max-pages)
             (not (and (stringp next) (plusp (length next))))))))

(defun history-meta (pages symbol dataset interval from to max-pages followed)
  (let ((first (or (first pages) (make-hash-table))))
    (list :symbol (or (gethash "symbol" first) symbol)
          :dataset (or (gethash "dataset" first) dataset)
          :interval (or (gethash "interval" first) interval)
          :from from
          :to to
          :quote "USD"
          :contemporaneously-signed
          (json-true-p (gethash "contemporaneouslySigned" first))
          :pages (length pages)
          :truncated (and pages (history-truncated-p pages max-pages followed))
          :endpoint (api-uri "/api/index/v1/history"
                             "symbol" symbol
                             "dataset" dataset
                             "interval" interval
                             "from" from
                             "to" to))))

(defun fetch-history (symbol &key dataset interval from to limit follow max-pages cache)
  (let ((ticker (canonicalize-symbol symbol))
        (dataset-name (canonicalize-dataset dataset))
        (interval-name (canonicalize-interval interval)))
    (unless ticker (error "A symbol is required."))
    (multiple-value-bind (start end) (history-bounds from to)
      (let ((pages (collect-history-pages ticker
                                          :dataset dataset-name
                                          :interval interval-name
                                          :from start
                                          :to end
                                          :limit limit
                                          :follow follow
                                          :max-pages max-pages
                                          :cache cache)))
        (values pages ticker dataset-name interval-name start end)))))

(defun ohlc-history (symbol &key (dataset :verified) (interval "1m") from to limit
                            (follow (null limit))
                            (max-pages *history-max-pages*)
                            (cache nil))
  "List of OHLC-BAR for SYMBOL, and a meta plist.
The default window is the last 24 hours.  GET-HISTORY without FROM/TO
walks from the start of the archive; this function does not.
INTERVAL defaults to 1 minute.  \"1d\", \"1h\", \"5m\", and the short
names d/h/m are accepted.  DATASET :verified is the signed archive.
:reconstructed is a labeled rebuild and is not a contemporaneous signature.
Verified bars are built from the observations, so a window that spans
pages is one bar per interval.  Reconstructed responses have candles
only; pieces of the same timestamp are merged.
VOLUME and ADJUSTED-CLOSE are NIL.  Pulse does not report trade volume.
:TRUNCATED in the meta plist is true when the walk stopped early.
Builder plan and above.  A lower plan signals PLAN-RESTRICTED."
  (multiple-value-bind (pages ticker dataset-name interval-name start end)
      (fetch-history symbol :dataset dataset :interval interval
                     :from from :to to :limit limit :follow follow
                     :max-pages max-pages :cache cache)
    (values (history-bars pages interval-name)
            (history-meta pages ticker dataset-name interval-name
                          start end max-pages follow))))

(defun price-history (symbol &key (dataset :verified) (interval "1m") from to limit
                             (follow (null limit))
                             (max-pages *history-max-pages*)
                             (cache nil))
  "List of (universal-time price) points, and the same meta plist as OHLC-HISTORY.
Verified history returns every observation in the window.  Reconstructed
history returns one point per candle, at the candle close.  The default
window is the last 24 hours."
  (multiple-value-bind (pages ticker dataset-name interval-name start end)
      (fetch-history symbol :dataset dataset :interval interval
                     :from from :to to :limit limit :follow follow
                     :max-pages max-pages :cache cache)
    (values (history-points pages interval-name)
            (history-meta pages ticker dataset-name interval-name
                          start end max-pages follow))))

(defun observation (at price)
  (let ((row (make-hash-table :test #'equal)))
    (setf (gethash "at" row) at
          (gethash "price" row) price
          (gethash "symbol" row) "BTC")
    row))

(behavior 'observations->bars
  (let ((bars (observations->bars
               (list (observation "2026-09-26T18:20:10.000Z" "100.5")
                     (observation "2026-09-26T18:20:40.000Z" "101.5")
                     (observation "2026-09-26T18:21:05.000Z" "99.25"))
               "1m")))
    (should= 2 (length bars))
    (should-be-true (ohlc-bar-p (first bars)))
    (should= (encode-universal-time 0 20 18 26 9 2026 0)
             (ohlc-bar-time (first bars)))
    (should= 100.5d0 (ohlc-bar-open (first bars)))
    (should= 101.5d0 (ohlc-bar-high (first bars)))
    (should= 100.5d0 (ohlc-bar-low (first bars)))
    (should= 101.5d0 (ohlc-bar-close (first bars)))
    (should= 99.25d0 (ohlc-bar-open (second bars)))
    (should= 99.25d0 (ohlc-bar-close (second bars)))
    (should-be-null (ohlc-bar-volume (first bars)))
    (should-be-null (ohlc-bar-adjusted-close (first bars)))
    (should= 7 (length (ohlc-bar-tuple (first bars))))
    (should-equal (ohlc-bar-tuple (first bars))
                  (first (ohlc-bars-for-ingest bars)))))

(behavior 'merge-candles
  (let* ((early (make-hash-table :test #'equal))
         (late (make-hash-table :test #'equal)))
    (setf (gethash "at" early) "2026-09-26T00:00:00.000Z"
          (gethash "open" early) 10
          (gethash "high" early) 12
          (gethash "low" early) 9
          (gethash "close" early) 11
          (gethash "at" late) "2026-09-26T00:00:00.000Z"
          (gethash "open" late) 11
          (gethash "high" late) 15
          (gethash "low" late) 8
          (gethash "close" late) 14)
    (let ((bars (merge-candles (list early late))))
      (should= 1 (length bars))
      (should= 10 (ohlc-bar-open (first bars)))
      (should= 15 (ohlc-bar-high (first bars)))
      (should= 8 (ohlc-bar-low (first bars)))
      (should= 14 (ohlc-bar-close (first bars))))))

(behavior 'history-fixture
  (let* ((page (load-fixture "history-btc.json"))
         (bars (history-bars (list page) "1m"))
         (points (history-points (list page) "1m")))
    (should= 2 (length bars))
    (should= 3 (length points))
    (should= 100.5d0 (second (first points)))
    (should-be-true (json-true-p (gethash "contemporaneouslySigned" page)))
    (should-string= "BTC" (getf (history-meta (list page) "BTC" "verified" "1m"
                                              "2026-09-26T18:20:00Z"
                                              "2026-09-26T18:22:00Z"
                                              20 t)
                                :symbol))
    (should-be-false (getf (history-meta (list page) "BTC" "verified" "1m"
                                         "a" "b" 20 t)
                           :truncated))))

(behavior 'history-bounds
  (let* ((end (encode-universal-time 0 0 12 26 9 2026 0))
         (start (encode-universal-time 0 0 12 25 9 2026 0)))
    (multiple-value-bind (from to) (history-bounds nil end)
      (should-string= (format-iso-8601 start) from)
      (should-string= (format-iso-8601 end) to))
    (multiple-value-bind (from to)
        (history-bounds "2026-09-01T00:00:00Z" "2026-09-02T00:00:00Z")
      (should-string= "2026-09-01T00:00:00Z" from)
      (should-string= "2026-09-02T00:00:00Z" to))))
