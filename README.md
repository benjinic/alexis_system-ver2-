# alexis_system

Alexis Tailor System 是一套使用 Flutter 與 Firebase 建立的跨平台裁縫店管理系統，涵蓋訂單、客戶、布料庫存、工作坊流程與 POS 功能。

## 環境需求

- Flutter SDK
- Dart SDK 3.10+
- Firebase CLI

## 安裝與執行

先安裝套件：

```bash
flutter pub get
```

本機啟動：

```bash
flutter run
```

## 測試模式指令

以 Flutter Debug 模式啟動：

```bash
flutter run
```

以 Chrome 啟動 Web 測試模式：

```bash
flutter run -d chrome
```

## 系統測試指令

### 建議標準流程（先 Analyze 再 Test）

先檢查靜態分析問題：

```bash
flutter analyze
```

再執行全部測試：

```bash
flutter test
```

### 常用測試指令

執行全部測試：

```bash
flutter test
```

只執行單一測試檔：

```bash
flutter test test/widget_test.dart
```

只跑特定測試名稱（可用關鍵字篩選）：

```bash
flutter test --plain-name "widget"
```

顯示更完整測試輸出（除錯時建議）：

```bash
flutter test --reporter expanded
```

### VS Code 一鍵測試流程

已提供一鍵 task：`Flutter: Analyze then Test`

操作方式：

1. 開啟 Command Palette（`Cmd + Shift + P`）
2. 輸入並選擇 `Tasks: Run Task`
3. 選擇 `Flutter: Analyze then Test`

### 上傳前最低檢查建議

至少執行以下兩個指令：

```bash
flutter analyze
flutter test
```

### 測試失敗時排查流程

1. 先重跑 analyze，先修編譯與 lint 問題再跑測試：

```bash
flutter analyze
```

2. 清理快取後重抓套件，再重跑測試：

```bash
flutter clean
flutter pub get
flutter test
```

3. 若只有特定測試失敗，先單檔重跑確認範圍：

```bash
flutter test test/widget_test.dart --reporter expanded
```

4. 若為 macOS/iOS 相關套件錯誤（CocoaPods），重新安裝 pods：

```bash
cd macos
pod install
cd ..
flutter test
```

5. 若仍失敗，建議回報時附上：

- `flutter doctor -v` 輸出
- `flutter analyze` 第一個錯誤訊息
- `flutter test --reporter expanded` 第一個失敗測試堆疊

## 上傳指令

### 上傳 Web 版本到 Firebase Hosting

**步驟一：確認套件最新**

```bash
flutter pub get
```

**步驟二：靜態分析（確保無錯誤）**

```bash
flutter analyze
```

**步驟三：執行測試**

```bash
flutter test
```

**步驟四：建置 Web Release 版本**

```bash
flutter build web --release --no-tree-shake-icons --no-wasm-dry-run --dart-define=FIREBASE_APPCHECK_RECAPTCHA_KEY=<site-key>
```

> `--no-tree-shake-icons`：避免 CupertinoIcons 字型 tree-shaking 導致 build 失敗。
> `--no-wasm-dry-run`：目前專案使用 `universal_html`，會觸發 Flutter wasm dry-run 相容性檢查警告；一般 JS Web build 請加上此參數。

**步驟五：登入 Firebase（首次或 Token 過期時）**

```bash
firebase login
```

若需要重新驗證目前帳號（例如權限異常或登入狀態過期）：

```bash
firebase login --reauth
```

**步驟六：部署到 Firebase Hosting**

```bash
firebase deploy --only functions,firestore:rules,storage,hosting --project alexis-tailor-system-2025
```

> 如需同時部署 Firestore Rules 或 Storage Rules：
> ```bash
> firebase deploy
> ```

### Gemini AI Proxy Secret 設定

Cloud Function `geminiProxy` 會從 Firebase Secret Manager 讀取 Gemini API key，不應在程式碼內硬編碼。

首次設定或換 key 時：

```bash
firebase functions:secrets:set GEMINI_API_KEY --project alexis-tailor-system-2025
```

更新 Functions：

```bash
firebase deploy --only functions --project alexis-tailor-system-2025
```

`geminiProxy`、`listGeminiModels` 與 `allocateOrderId` 會驗證 Firebase ID token、Firebase App Check token，並套用每分鐘 rate limit。前端呼叫時必須帶：

- `Authorization: Bearer <Firebase ID token>`
- `X-Firebase-AppCheck: <Firebase App Check token>`

Web build 時必須提供 Firebase App Check reCAPTCHA v3 site key：

```bash
flutter build web --release --no-tree-shake-icons --no-wasm-dry-run --dart-define=FIREBASE_APPCHECK_RECAPTCHA_KEY=<site-key>
```

### SSR Function Secret 設定

SSR Functions 的 service account private key 需放在 Firebase Secret Manager，不應以 plain environment variable 部署。

已遷移的 Secret：

- `ALEXIS_PRIVATE_KEY`

已使用 Secret 的 Functions：

- `ssralexisbespoke`
- `ssralexistailorsystem20`

重新部署 SSR Functions 時，請確認 `ALEXIS_PRIVATE_KEY` 仍以 Secret Manager 綁定，不要放回 plain env。

### 部署後安全與回歸檢查

部署後建議執行以下檢查：

```bash
node tool/audit_functions_env.js
FIREBASE_APPCHECK_TOKEN=<token> node tool/smoke_gemini_proxy.js
```

`audit_functions_env.js` 只輸出 env key 名稱，不輸出 secret value；若發現 plain sensitive env，會以非 0 exit code 結束。

`smoke_gemini_proxy.js` 會建立臨時 Firebase anonymous user 測試 authenticated proxy，完成後會刪除臨時 user。因為 proxy 已啟用 App Check，執行前需提供有效 `FIREBASE_APPCHECK_TOKEN`。

完整部署檢查流程：

```bash
flutter analyze
flutter test
flutter build web --release --no-tree-shake-icons --no-wasm-dry-run --dart-define=FIREBASE_APPCHECK_RECAPTCHA_KEY=<site-key>
firebase deploy --only functions,firestore:rules,storage,hosting --project alexis-tailor-system-2025
node tool/audit_functions_env.js
FIREBASE_APPCHECK_TOKEN=<token> node tool/smoke_gemini_proxy.js
```

## Web 字型自救方案（MaterialIcons 無法顯示）

若瀏覽器 Console 出現以下訊息，通常代表打包進去的 MaterialIcons 字型檔異常，或被舊版 Service Worker / 快取干擾：

- Failed to load font MaterialIcons
- Verify that assets/fonts/MaterialIcons-Regular.otf contains a valid font

### 已採用修正

1. 專案內提供可用字型，避免依賴本機 Flutter SDK 快取：
	- `assets/fonts/MaterialIcons-Regular.ttf`
2. 在 `pubspec.yaml` 明確覆蓋 MaterialIcons family：
	- `flutter -> fonts -> family: MaterialIcons`
3. `web/flutter_bootstrap.js` 設定較長 Service Worker timeout（12000ms）
4. `firebase.json` 對 `index.html`、`flutter_bootstrap.js`、`flutter_service_worker.js` 設定 `Cache-Control: no-cache`

### 建議排查順序

1. 重新建置：

```bash
flutter build web --release --no-tree-shake-icons --no-wasm-dry-run
```

2. 部署：

```bash
firebase deploy --only hosting --project alexis-tailor-system-2025
```

3. 使用者端驗證：
	- macOS Chrome 強制重整：Cmd + Shift + R
	- 若仍異常，改用無痕視窗開站（排除 Service Worker 舊快取）

4. 線上快速檢查：

```bash
curl -s https://alexis-tailor-system-2025.web.app/assets/FontManifest.json
```

預期應看到 MaterialIcons 指向專案字型路徑（ttf），而不是舊的 otf。

## 專案結構

- `lib/main.dart`: App 入口與路由設定
- `lib/layouts/`: 共用版面配置
- `lib/pages/`: 主要功能頁面
- `lib/components/`: 可重用 UI 元件
- `lib/services/`: Firestore、匯出、列印等服務
- `test/`: 測試檔案

## 備註

- Firebase 專案 ID：`alexis-tailor-system-2025`
- 部署前建議先執行 `flutter test` 與 `flutter analyze`

---

## 更新紀錄

### 2025-05-19

**文字輸入強制大寫**
- 所有姓名、布料名稱、單位、店名等文字欄位自動轉換為大寫輸入
- 搜尋欄不受影響（保持原始輸入，後台以 toLowerCase 比對）

**搜尋欄連續輸入修正（Flutter Web）**
- 修正 `fabric_page.dart` 及 `pos_page.dart` 搜尋欄在 Flutter Web 下每輸入一個字就失去焦點的問題
- 根本原因：搜尋 TextField 位於 StreamBuilder 內，`onChanged` 呼叫 `setState` 觸發 StreamBuilder 重建導致焦點遺失
- 解法：將搜尋 TextField 移至 StreamBuilder 外層，避免重建影響輸入焦點

**布料庫存重覆名稱檢查**
- 新增/編輯布料時，儲存前自動檢查名稱是否已存在（不分大小寫）
- 重覆名稱顯示提示：`布料名稱「XXX」已存在，請使用不同名稱`
- 名稱空白時顯示提示：`請輸入布料名稱`
- 編輯現有布料時排除自身，不會誤判為重覆

**Gemini AI 升級**
- Cloud Function `geminiProxy` 升級使用 `gemini-2.5-pro` 模型
- Cloud Function `geminiProxy` 改用 Secret Manager 讀取 `GEMINI_API_KEY`
- Cloud Function `geminiProxy` 與 `listGeminiModels` 需通過 Firebase ID token 驗證
- SSR Functions 改用 Secret Manager 讀取 `ALEXIS_PRIVATE_KEY`
- 新增部署後 Functions env audit 與 Gemini proxy smoke test 工具
- 布料 AI 掃描辨識精度提升

**收據格式調整**
- 收據字型大小整體增加 2pt
- 移除布料明細中的 `Code: xxx` 欄位
- POS 購物車每項布料顯示材料成本（`Mat: $x.x`）及外包成本（`Out: $x.x`）
