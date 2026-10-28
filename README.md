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

### 員工名單（staff）與存取控制

Firestore / Storage 規則與所有 Cloud Functions 都要求呼叫者的 uid 存在於 Firestore `staff/{uid}`，只登入 Firebase Auth 並不足夠（匿名或自行註冊的帳號會被拒絕）。

- `staff/{uid}` 不允許 client 寫入，只能由 Cloud Functions（Admin SDK）或 Firebase Console 寫入；使用者只能讀取自己的那筆。
- 新增員工：Settings → 員工帳號管理，會呼叫 `createStaffAccount` 函式建立 Auth 帳號並加入名單。
- 手動加入員工：Firebase Console → Firestore → `staff` collection，文件 ID 填該帳號的 UID，欄位 `email`（string）。
- Firebase Auth 應停用 Anonymous / Google 登入，並在 Authentication → Settings → User actions 關閉「Enable create (sign-up)」。
- `tool/smoke_gemini_proxy.js` 使用匿名帳號，現在會被 403 拒絕，僅能用於確認未授權帳號無法呼叫 proxy。

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
firebase login --reauth
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

## 待處理事項

- **`orders` 同 `order_items` 寫入邏輯有重疊，之後要整理。** 而家金額、成本同摘要喺兩邊都有計：app 落單時計一次（`pos_page.dart` 的 `_processOrder`、`CostCalculationService`），Cloud Functions（`functions/index.js` 的 `syncOrderDerivedFields`）收到 `orders` 或 `order_items` 寫入又再計一次，兩邊規則唔完全一致。之後要決定邊個欄位由邊一方負責，只計一次。

---

## 系統使用說明

### 登入

系統使用 Firebase Authentication。開啟網址後若未登入，系統會自動跳轉至登入頁面。使用指定的電子郵件帳號與密碼登入即可。

> 注意：請務必從根網址（`https://alexis-tailor-system-2025.web.app/`）進入，直接開啟深層連結（如 `#/orders`）在未登入狀態下會出現 Firestore 權限錯誤。

---

### 儀表板（Dashboard）

總覽當日與本月的核心業績數據：

- **KPI 卡片**：今日訂單數、本月收入、待收款金額、客戶總數
- **趨勢對比**：每張卡片與上期數據比較，顯示升跌百分比
- **快速入口**：Pending 訂單、Outstanding（未收款）訂單

---

### POS 收銀（POS）

用於建立新訂單或編輯現有訂單：

1. **選擇客戶**：輸入名稱搜尋現有客戶，或直接輸入新客戶名稱
2. **新增服裝項目**：選擇服務（西裝、褲子等）→ 設定布料、布料用量、數量
3. **金額設定**：調整折扣、訂金、付款方式
4. **交貨日期**：可選設定交貨日
5. **確認建立**：按「建立訂單」完成

> 布料欄位支援以布料庫存 ID 搜尋，選中後自動填入成本計算。
> 也可以從 Bespoke 匯入訂製訂單，見下方「訂製訂單（Bespoke）」。

---

### 訂單管理（Orders）

列出所有 POS 訂單：

| 功能 | 操作 |
|------|------|
| 搜尋 | 輸入客戶名稱、訂單號、布料名稱或服務名稱 |
| 篩選 | Pending（未確認）/ Outstanding（未收款） |
| 查看詳情 | 點選任一訂單卡片 |
| 編輯訂單 | 詳情對話框 → Edit 按鈕 |
| 列印收據 | 詳情對話框 → Print 按鈕 |
| 相片記錄 | 詳情對話框 → Photos 按鈕 |
| 確認訂單 | 詳情對話框 → Confirm Order（Pending → Confirmed） |
| 標記完成 | 詳情對話框 → Mark as Complete（Confirmed → Completed） |
| 布料訂購 | 詳情對話框 → Mark Fabric Ordered / Fabric Ready |
| 匯出 CSV | AppBar 右上角下載按鈕 → 選擇日期範圍 → 匯出 |

**訂單狀態流程：** `Pending → Confirmed → Completed`

**CSV 匯出**：按下下載按鈕後，可選擇開始日期與結束日期；兩者均不選則匯出全部訂單。

---

### 客戶管理（Clients）

管理客戶檔案與聯絡紀錄：

- **新增客戶**：右上角「＋」按鈕，填寫姓名（必填）、電話、電郵
  - 姓名與電話均設有防重複檢查
  - 姓名自動轉換為大寫
- **搜尋客戶**：輸入名稱或電話號碼
- **客戶詳情頁**：顯示訂單歷史、總消費金額、客戶等級（New / Regular / VIP）
  - 編輯基本資料（姓名、電話、電郵）
  - 管理體型尺寸（肩寬、胸圍、腰圍等）
  - 新增跟進日期（Next Follow-Up）
  - 記錄聯絡日誌（通話 / 試身 / 訊息 / 備註）

**客戶等級標準：**

| 等級 | 總消費門檻 |
|------|-----------|
| New | < $10,000 |
| Regular | $10,000 – $49,999 |
| VIP | ≥ $50,000 |

---

### 布料庫存（Fabric）

管理布料庫存：

- **新增布料**：填寫名稱、類別、單位、每單位成本、零售價、庫存數量、補貨警戒線
- **編輯布料**：點選布料卡片 → Edit
- **庫存調整**：直接在卡片上加減庫存數量
- **批次 AI 掃描**：AppBar 相機按鈕 → 上傳供應商圖片或布卡照片
  - AI 自動辨識並提取：名稱、類別、顏色、成本、零售價
  - 核對表確認後再批次入庫
  - 同名布料自動標示「已存在」並鎖定，防止重複入庫

---

### 工作坊（Shop）

追蹤生產進度：

- **工作單列表**：顯示所有進行中的生產項目
- **優先標記**：標為 Urgent 的訂單在導覽欄顯示紅色數字角標
- **布料狀態**：每張工作單可標記布料是否已訂購
- **逾期提示**：超過交貨日的工作單以紅色顯示

---

### 訂製訂單（Bespoke）

訂製西裝訂單功能已拆出為獨立 Flutter App：`../alexis_bespoke`（https://alexis-bespoke-staff.web.app，GitHub：`benjinic/Alexis_bespoke_form`），與本系統共用同一個 Firebase 專案與登入帳號。

> **2026-10-13**：這個 App 原本用 `alexis-bespoke.web.app`，但這個網址同時被另一個 Next.js 客人購物網站（`../alexis_website`，`benjinic/alexis_website`）使用，兩邊部署會互相覆蓋。已改為 `alexis-bespoke-staff.web.app`，`alexis-bespoke.web.app` 留給客人購物網站。`alexis_website` 那邊需要重新部署才能恢復正常（目前還顯示舊的 Flutter 內容）。
本系統不再包含 Bespoke 頁面與導覽入口，但 Firestore collection `bespoke_orders` 的安全規則仍保留在本專案的 `firestore.rules`（同一個 Firebase 專案共用一份規則）。

**分工**：Bespoke 只負責建立訂製訂單並上傳（沒有單號、不計價）；正式訂單、單號、價錢、成本、庫存扣減全部由本系統 POS 處理。

**從 Bespoke 匯入（POS 頁右上角「從 Bespoke 匯入」）**

1. 選擇一張「待匯入」的 Bespoke 訂單。
2. 客人：優先用訂單記錄的 `customerId` 對回同一位客人，找不到才用電話、姓名比對；再找不到就照舊建立新客人。
3. 訂金、交貨日、備注（電話、每件衣服的布料與設計規格）預填到 POS；同款多件會在備注加序號（例如「外套 1」「外套 2」）。
4. **每件衣服各開一次原本的「新增項目」視窗**（`OrderItemDialog`），已預填服務、價錢、布料、用量；計價與成本只由這個視窗處理，Bespoke 不重複實作。服務優先用 Bespoke 已選的（`serviceId`，其次 `serviceName`），沒選才依衣服類型關鍵字猜。按取消會略過該件。
5. 儲存時由 Cloud Function `allocateOrderId` 分配最新單號，並回寫 `posOrderId` / `posOrderNo` / `importedAt` 到該張 `bespoke_orders`。

**`bespoke_orders` 安全規則**（`firestore.rules`）

- 讀取：員工。建立：員工，且不能預先帶 `posOrderId`、`posOrderNo`、`importedAt`。
- 更新有三種情況：① POS 匯入（訂單未匯入時，只寫上述三個欄位）；② 員工編輯訂單內容（訂單未匯入時，不可碰上述三個欄位）；③ 已匯入後員工只可改 `items`（Bespoke 的「編輯款式」用），其餘欄位不可再改。
- 刪除：只限未匯入（`posOrderId` 為空）的訂單。

**同步注意**：`lib/services/bespoke_import_service.dart` 內有一份設計欄位的中文標籤對照表，與 Bespoke 的 `lib/models/tailor_design_options.dart` 對應，修改款式選項時兩邊都要更新。相關程式：`lib/services/bespoke_cart_mapper.dart`（預填邏輯）、`lib/pages/pos_page.dart` 的 `_importFromBespoke()`。

---

### Cost & Profit 分析

（從 Dashboard 進入或透過連結開啟）

- 每筆訂單的收入、成本、利潤明細
- 按日期 / 利潤率 / 收入排序
- 虧損訂單自動顯示紅色警示橫幅
- 趨勢對比：與上期同類數據比較（升跌箭頭）

---

### 設定（Settings）

- **主題色**：自訂主色調
- **語言**：繁體中文 / 簡體中文 / English
- **深色模式**：系統跟隨 / 強制深色 / 強制淺色
- **體型量度欄位**：自訂客戶量身時的量度項目

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

### 2026-07-21

**布料批次 AI 掃描（Service 層）**
- `AiFabricScanResult` 新增 `costPerUnit` 與 `retailPrice`（`double?`，選填），不影響現有單筆掃描呼叫方
- `AiFabricScanService` 新增 `scanFabricLabelBatch()`：接收相同的 `imageBytes + mimeType`，回傳 `List<AiFabricScanResult>`
- 新增 `_batchPrompt`：同時支援兩種照片格式（供應商文字清單 / 多張實體布卡並排），要求 Gemini 辨識所有布料並回傳 JSON 陣列
- 新增 `parseGeminiResponseBatch()` / `parseFabricJsonArrayText()`：容錯剝除 markdown code fence、解析失敗時回傳空 `[]` 不 crash
- 新增 `_parseNullableDouble()`：容錯處理 Gemini 回傳的 `num / String / null` 型別差異
- 現有 `scanFabricLabel()` 及所有 UI 檔案均未修改

**布料批次 AI 掃描（UI 層）**
- `fabric_page.dart` AppBar 新增 `Icons.document_scanner` 按鈕，觸發批次掃描流程
- `_BatchScanManagerDialog`（StatefulWidget）：每次點擊「選擇圖片」可 Shift/Ctrl-click 選多張；選後逐張呼叫 `scanFabricLabelBatch()`，每張有獨立 log 條目（三態：掃描中 / 完成 / 失敗）；掃描完畢後可再次追加圖片
- `_showBatchReviewDialog()`：N 筆可編輯列表（名稱 / 類別 Dropdown / 成本 / 零售價 / checkbox）；空名稱列自動標紅並鎖定 checkbox；與現有庫存重名顯示「已存在」badge；批次內重名顯示「批次重複」badge；頂部即時顯示「共辨識 N 筆，將入庫 M 筆」；「全部入庫」按鈕逐筆呼叫 `addMaterial()` 並顯示進度；取消不寫入任何資料
- 新增 `_BatchRow` / `_ScanLogEntry` / `_LogStatus` 輔助類別；所有顏色沿用 M3 colorScheme token
- 建議新增 l10n key：`batchScan` / `batchScanResults` / `batchScanning` / `batchImport`

### 2026-08-21

**Cost & Profit 頁面強化**
- CP-1：所有硬編碼色（`Colors.white/grey.*`）全換為 M3 `colorScheme` 語義 token，支援深色模式
- CP-2：新增 `_SortBar` chip UI（日期 / 利潤率 / 收入）+ 排序方向切換按鈕
- CP-3：計算 `lossCount/totalLoss`，有虧損時顯示 `_LossAlert` 紅色橫幅
- CP-4：`_filterOrdersByLastPeriod()` 計算上期數據，KPI 卡片新增趨勢箭頭（`trending_up/down/flat`）與 `±%` / `±pp` 標示

**布料批次 AI 掃描修正**
- 解析強化：`parseFabricJsonArrayText` 新增第二層解析，從回應中截取 `[…]` 區段，處理 Gemini 在 JSON 前後加說明文字的情況
- 掃描失敗時 log 顯示實際錯誤原因（例如「API 錯誤 401」），而非通用「掃描失敗」
- 「選擇圖片」改用 `pickMultiImage()`，開啟 `<input multiple>` 檔案選擇器，用戶可 Shift/Ctrl-click 一次選取多張；選完後逐張自動掃描，每張獨立更新 log

### 2026-08-22

**布料批次核對表欄位完整（FB-6）**
- `_BatchRow` 新增 `colorCtrl`（AI 自動填入大寫顏色）、`unitCtrl`（預設 M）、`isOnline`（Switch）、`costCtrl`、`retailCtrl`
- 核對表改為雙行佈局：上行（名稱 / 類別 / 上架開關），下行（顏色 / 單位 / 成本 / 零售價）
- `addMaterial()` 呼叫補傳所有新欄位，與單筆新增欄項完全對齊

**批次掃描防重複（FB-7）**
- DB 已存在相同名稱的布料：自動取消勾選並鎖定 checkbox（無法手動勾回，無法入庫）
- 核對表列顯示「已存在」badge；`rowWillSave` 邏輯排除 DB 重名行
- 批次內出現相同名稱：顯示「批次重複」badge 但不鎖定，由用戶決定保留哪一筆

**客戶新增防重複（CD-9）**
- 儲存前呼叫 `getCustomersStream().first` 比對現有客戶資料
- 名稱完全相符（不分大小寫）時阻擋並顯示  錯誤 SnackBar
- 電話號碼不為空時亦檢查是否重複

**批次掃描圖片自動入庫（FB-8）**
- 新增 `_ScanImageGroup` data class，將每張掃描圖的 bytes 與辨識結果綁定
- 核對表每行顯示來源圖縮圖（44×44 px）供對照
- 「全部入庫」前先對每個不同來源圖上傳一次（`imageUrlCache` Map 去重），避免同一張圖重複上傳
- 每筆布料的 `MaterialItem.imageUrl` 自動填入對應上傳 URL

### 2026-09-24 ~ 26（Bespoke 整合）

- POS 新增「從 Bespoke 匯入」：逐件開原本的新增項目視窗預填，同款多件備注加序號。
- `firestore.rules`：`bespoke_orders` 更新規則分三種情況（POS 匯入／未匯入時員工編輯／已匯入後只改 `items`），刪除限未匯入。
- 布料與訂單圖片上傳依實際檔案內容判斷格式（JPEG／PNG／WebP），不再一律標成 `image/jpeg`；Storage 規則只接受這三種，其他格式會略過上傳。
- 新增 `tool/build_web.sh`：固定帶 App Check reCAPTCHA key 並檢查是否編進去，建置請用它。
- 已知未上線：`lib/components/icon_text.dart` 改成顯示真正圖示的修正（commit `74d252a`）只在本機。`IconText` 目前線上仍以中文方括號文字取代圖示（例如「[儀表板]」），是早期 MaterialIcons 字型載入失敗時的緊急替代方案，字型已修好但元件沒換回來。
