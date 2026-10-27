#!/usr/bin/env bash
# Local servers for example/integration_test/vpn_e2e_test.dart (Android emulator).
# Everything listens on 127.0.0.1 only; the emulator reaches it as 10.0.2.2.
#
#   SING_BOX_BIN=/path/to/sing-box example/integration_test/server/run_e2e_server.sh
#
# * sing-box: shadowsocks :8388, vless :10086, 203.0.113.80 -> 127.0.0.1 rewrite
# * HTTP :18080 serving probe.txt and the test rule-sets (compiled to .srs)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${SING_BOX_BIN:?set SING_BOX_BIN to a sing-box 1.14 binary}"
for rules in "$DIR"/rules/*.json; do
  "$BIN" rule-set compile -o "$DIR/www/$(basename "${rules%.json}").srs" "$rules"
done
python3 -m http.server 18080 --bind 127.0.0.1 --directory "$DIR/www" &
HTTP_PID=$!
trap 'kill $HTTP_PID 2>/dev/null' EXIT
"$BIN" run -c "$DIR/server.json"
