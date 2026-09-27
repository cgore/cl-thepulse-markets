# cl-thepulse-markets

**[View PDF Documentation](documentation/thepulse-markets.pdf)**

A Common Lisp client for the [Pulse Verity Index](https://thepulse.markets/developers).
This is not an official Pulse library.  It wraps the public read API.

Pulse publishes a signed USD index for crypto tickers.  A successful
price is an ECDSA P-256 signature over the symbol, the exact price text,
the timestamp, and the grade.  You can check that signature with the
published key ring, without asking Pulse whether the print is still valid.

The client covers the documented REST surface: signed prices and batches,
the keyless BTC/ETH/SOL sample, settlement prints, metadata, verified and
reconstructed history, research comparisons, source health, the unsigned
Verity breadth reads, and the public status, symbol, terms, and key-ring
endpoints.

The WebSocket at `/api/index/v1/stream` is not wrapped.  The developer
console (`/api/developers/...` on `thepulse.markets`, including keys,
billing, and webhooks) is a browser session, not this API key, and is not
wrapped either.  Hosted MCP is a separate protocol; this library speaks
HTTP.

- Docs: [thepulse.markets/developers](https://thepulse.markets/developers)
- API origin: `https://mcp.thepulse.markets`
- Github: [cgore/cl-thepulse-markets](https://github.com/cgore/cl-thepulse-markets)

## Install

Clone next to your other local systems (or symlink the `.asd` into
`~/programming/lisp/systems/`):

```lisp
(asdf:load-system :thepulse-markets)
(in-package :thepulse-markets)
```

Depends on `babel`, `cl-base64`, `dexador`, `function-cache`, `ironclad`,
`quri`, `sigma`, and `yason`.

## Authentication

On load the library looks for a gitignored Lisp file:

```
source/configuration/local-configuration.lisp
```

That file is loaded in the `thepulse-markets/rest-api` package, the same
way [limbic.fi](https://github.com/cgore/limbic.fi) loads
`local-configuration.lisp`.  It can rebind `*api-key*` and the other
parameters:

```lisp
(defparameter *api-key* "pidx_your_key_here")
```

When that file is missing, or it does not leave a usable key, the
library reads `PULSE_API_KEY`, then `THEPULSE_MARKETS_API_KEY`.  The
environment is the backup for a checkout that has no local file.  You
can also set the key in the image:

```lisp
(use-key "pidx_your_key_here")
(use-keyless)
(reload-local-configuration)
```

Create a key at [thepulse.markets/developers](https://thepulse.markets/developers).
The key is sent as `Authorization: Bearer` on keyed calls only.  Public
reads (health, symbols, status, the key ring, terms) do not send it, so a
status poll does not spend the monthly allowance.  Redirects are not
followed.

With no usable key, `price` still answers `:btc`, `:eth`, and `:sol` from
the public sample.  Anything wider signals `needs-key`.  Placeholder
strings such as `pidx_your_key_here` count as no key.

Do not commit a real key.  The local configuration file is gitignored.
A 401 is `unauthorized`.  A 403 is
`plan-restricted` (history, research, and source health are plan-gated).
A 429 is either `rate-limited`, which this client retries, or
`monthly-limit`, which it does not.  The monthly allowance resets at the
next UTC month.  Replacing the key does not reset it.

## A signed price

```lisp
(price :btc)
(nth-value 1 *)   ; the print: symbol, priceText, at, grade, signature, kid

(verify-print (nth-value 1 (price :btc)))
```

`price` returns the number.  The second value is the raw print (a Yason
hash table).  Keep `priceText` exactly as it arrived if you store the
print; the signature is over that text, not over a float you print again.

`verify-print` checks the v1 signature locally.  `:version :v2` checks
the wider canonical string Pulse attaches under `v2`, which includes
tier, confidence, cadence, and the interval.  `:version :both` requires
v1 and, when a v2 block is present, v2 as well.  A true result does not
cover fields that are outside the canonical string you asked about.
`deltaMs` on a settlement print is never signed.

```lisp
(prices '("BTC" "ETH"))
;; (:symbol "BTC" :price 84000.0d0 :print #<hash-table> :code nil :message nil)

(settlement-print :btc (get-universal-time))
;; values: price, print, deltaMs

(verity-price :btc)   ; unsigned breadth read; verify-print does not apply
```

An unknown ticker signals `unsupported-symbol` on `/price`.  Inside
`prices` it is one row with `:price nil` and a `:code`, and the other
rows still come back.  An unavailable price is not zero.

Grades are `consensus` (3 or more independent sources), `blended` (2),
and `indicative` (1).  Indicative is a real book with no second opinion.
Pulse says not to settle on it.

## History and candlesticks

`ohlc-history` returns `ohlc-bar` objects and a meta plist.  The default
window is the last 24 hours, not the start of the archive.  The default
interval is one minute.  `"1d"`, `"1h"`, `"5m"`, and the short names
`d` / `h` / `m` work.

```lisp
(ohlc-history :btc :interval "1d"
              :from (encode-universal-time 0 0 0 1 9 2026 0)
              :to   (encode-universal-time 0 0 0 26 9 2026 0))

(multiple-value-bind (bars meta)
    (ohlc-history :eth :interval "5m")
  (list (length bars)
        (getf meta :quote)                       ; "USD"
        (getf meta :contemporaneously-signed)    ; T for dataset verified
        (getf meta :truncated)
        (getf meta :endpoint)))
```

`:dataset :verified` (the default) is the signed archive.  Bars are built
from those observations, so a window that spans pages is one bar per
interval.  `:dataset :reconstructed` is a labeled rebuild from older
source data.  It is not a contemporaneous signature, and the payload says
so.  Both are Builder plan and above.  A lower plan signals
`plan-restricted`.

Volume and adjusted close are `nil`.  Pulse counts observations; it does
not report trade volume.  That count stays on the raw `get-history`
payload.  Do not ingest it as share volume.

`price-history` is the `(universal-time price)` list.  Universal time
drops the fractional second.  The original `at` string is on the raw
payload.

`:limit` asks for one page and does not follow the cursor.  Pass
`:follow t` to walk pages anyway.  The walk stops after
`*history-max-pages*` (20).  `:truncated t` in the meta plist means the
window is incomplete.

This library does **not** depend on
[candlesticks](https://github.com/cgore/candlesticks).  An application
can load both:

```lisp
(ql:quickload '(:thepulse-markets :candlesticks))

(multiple-value-bind (bars meta)
    (thepulse-markets:ohlc-history :btc :interval "d"
                                   :from (encode-universal-time 0 0 0 1 9 2026 0)
                                   :to   (encode-universal-time 0 0 0 26 9 2026 0))
  (candlesticks:ingest-candlesticks
   "BTC" "USD" "d"
   (thepulse-markets:ohlc-bars-for-ingest bars)
   :source-name "Pulse"
   :source-kind "api"
   :endpoint (getf meta :endpoint)
   :numerator-name "Bitcoin"
   :numerator-type "cryptocurrency"
   :denominator-name "US Dollar"
   :denominator-type "currency"))
```

## The rest of the API

Every documented REST read has a `get-*` function in
`thepulse-markets/rest-api` (re-exported from `thepulse-markets`).
Keyword arguments are the query parameters.  Symbols are uppercased.
Lists become comma-separated.  Results are Yason hash tables (arrays as
vectors, booleans as symbols).

```lisp
(get-symbols)
(get-health)
(get-pubkey)
(get-verity-catalog :band :real-time :status :consensus :limit 20)
(get-metadata '(:btc :eth))
(get-research-compare '("BTC" "ETH") :interval "1d")
(get-source-health)          ; Commercial and Enterprise
```

Live price calls default to `:cache nil`.  Reference reads (symbols, the
key ring, catalog, terms) are cached.  The key ring is cached for five
minutes.  Pass `:cache nil` or `:cache t` to override.  The general cache
is `*api-cache-timeout-seconds*` (60), and it is partitioned so one key's
body is not reused for another.  The cache key is a short hash of the
API key, not the key itself.

`get-price` always hits `/price` and requires a key.  `price` is the one
that falls back to the sample.

## Testing

Specs are `sigma/behave` `behavior` / `should` forms, same style as
[sigma](https://github.com/cgore/sigma).  Pure helpers, including a
checked-in Bitcoin print and the public key ring, run at load time.
`asdf:test-system` reloads the sources so those assertions run again.

```lisp
(asdf:test-system :thepulse-markets)
```

That does not hit the network.  To also call Pulse (health, a Bitcoin
price and its signature, the keyless Ethereum sample, a batch with one
unknown ticker, and 30 minutes of BTC candles):

```
THEPULSE_MARKETS_LIVE_TESTS=1
```

A `local-configuration.lisp` key, or `PULSE_API_KEY` in that environment,
unlocks the keyed calls.  Without either,
the keyed live checks fail and the sample check still runs.

## License

Copyright (c) 2026, Christopher Mark Gore,  
Soli Deo Gloria,  
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
* Neither the name of Christopher Mark Gore nor the names of other contributors may be used to endorse or promote products derived from this software without specific prior written permission.

**THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS *"AS IS"* AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.**
