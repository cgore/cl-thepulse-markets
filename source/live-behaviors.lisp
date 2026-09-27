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

;;;; Live Pulse checks.  Loaded only by TEST-OP when
;;;; THEPULSE_MARKETS_LIVE_TESTS is set, so ordinary loads never hit the network.
;;;; A local-configuration.lisp key, or PULSE_API_KEY
;;;; (or THEPULSE_MARKETS_API_KEY), unlocks the keyed calls.
;;;; The sample and the public health probe do not need it.

(in-package #:thepulse-markets)

(behavior 'health-live
  (let ((health (get-health :cache nil)))
    (should-be-a 'hash-table health)
    (should-string= "operational" (gethash "status" health))))

(behavior 'price-live
  (multiple-value-bind (px print)
      (price :btc :cache nil)
    (should-be-a 'number px)
    (should-be-true (plusp px))
    (should-string= "BTC" (gethash "symbol" print))
    (should-be-true (stringp (gethash "priceText" print)))
    (should-be-true (verify-print print))
    (should-be-true (verify-print print :version :v2))
    (should-be-true (verify-print print :version :both))))

(behavior 'sample-live
  (let* ((*api-key* nil)
         (px nil)
         (print nil))
    (multiple-value-setq (px print) (price :eth :cache nil))
    (should-be-true (plusp px))
    (should-be-true (json-true-p (gethash "sample" print)))
    (should-be-true (verify-print print))))

(behavior 'unsupported-symbol-live
  (handler-case
      (progn
        (price "NOTAREALSYMBOLZZ" :cache nil)
        (should-be-true nil))
    (unsupported-symbol (condition)
      (should-string= "UNSUPPORTED_SYMBOL" (api-error-code condition)))))

(behavior 'prices-live
  (let ((rows (prices '("BTC" "ETH" "NOTAREALSYMBOLZZ") :cache nil)))
    (should= 3 (length rows))
    (should-be-true (plusp (getf (first rows) :price)))
    (should-be-true (getf (first rows) :print))
    (should-string= "UNSUPPORTED_SYMBOL" (getf (third rows) :code))
    (should-be-null (getf (third rows) :price))))

(behavior 'ohlc-history-live
  (handler-case
      (let* ((end (get-universal-time))
             (start (- end (* 30 60))))
        (multiple-value-bind (bars meta)
            (ohlc-history :btc :interval "1m" :from start :to end :cache nil)
          (should-be-true (>= (length bars) 1))
          (should-be-true (ohlc-bar-p (first bars)))
          (should-be-a 'integer (ohlc-bar-time (first bars)))
          (should-be-a 'number (ohlc-bar-close (first bars)))
          (should-be-true (plusp (ohlc-bar-close (first bars))))
          (should-string= "BTC" (getf meta :symbol))
          (should-string= "1m" (getf meta :interval))
          (should-string= "USD" (getf meta :quote))
          (should-be-true (search "/api/index/v1/history" (getf meta :endpoint)))
          (should-be-false (getf meta :truncated))
          (should= 7 (length (ohlc-bar-tuple (first bars))))))
    ((or plan-restricted rate-limited monthly-limit) (condition)
      (declare (ignore condition))
      t)))
