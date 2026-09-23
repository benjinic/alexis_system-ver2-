#!/usr/bin/env bash
# 建置 Web 版本。必須帶 reCAPTCHA Enterprise site key（公開金鑰，非機密），
# 否則 Cloud Storage 的 App Check 會擋住圖片上傳（403）。
set -euo pipefail
cd "$(dirname "$0")/.."
flutter build web --release --no-tree-shake-icons --no-wasm-dry-run \
  --dart-define=FIREBASE_APPCHECK_RECAPTCHA_KEY=6Lf8BMotAAAAAJQUddHoFMVwPs2_YzpcFyGxNYw5 "$@"
grep -q "6Lf8BMotAAAAAJQUddHoFMVwPs2_YzpcFyGxNYw5" build/web/main.dart.js \
  && echo "OK: build 已包含 App Check key" \
  || { echo "錯誤：build 沒有包含 App Check key" >&2; exit 1; }
