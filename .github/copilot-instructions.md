# Copilot AI Agent Instructions for `alexis_system`

A Flutter cross-platform tailor shop management system (mobile, desktop, web) with Firestore backend, focusing on orders, workshop job tracking, inventory, and POS operations.

## Critical Architecture Patterns

**Authentication & Routing:**
- Firebase Auth gates entire app via `AuthWrapper` in `main.dart` (StreamBuilder on `FirebaseAuth.instance.authStateChanges()`)
- Route names are string-based (e.g., `/pos`, `/workshop`), all defined in `MaterialApp.routes` in `main.dart`
- `MainLayout` wraps all pages with persistent sidebar navigation; pages are children of `MainLayout`, not standalone

**Data Flow (Firestore-Centric):**
- `DatabaseService` is the **only** data gateway; instantiate fresh in each page's `initState()` or as field
- Collections: `orders`, `order_items`, `inventory`, `workshop_orders`, `customers`, `services`
- Models use `fromMap(id, Map)` constructor from Firestore snapshots; `toJson()` for writes
- **Streams over futures**: Most pages use `StreamBuilder` with `getOrdersStream()`, `getWorkshopOrdersStream()` for live updates; avoid one-off fetches unless UI doesn't need reactivity

**State Management (Minimal):**
- All pages are `StatefulWidget`; no provider/bloc/riverpod—use local `State` variables and `setState()` for UI refresh
- Text controllers and scroll controllers are disposed in `dispose()`
- For cross-page data: use Firestore as source of truth, not local state

**Workshop Status Workflow (Core Domain Logic):**
- `WorkshopStatus` is a strict enum: `measuring` → `cutting` → `sewing` → `finishing` → `completed` → `archived`
- Status transitions via `_updateOrderStatus()` in `workshop_page.dart` atomically update progress (0%, 25%, 50%, 75%, 100%)
- Never allow backward transitions; validate new status before Firestore write
- `workshop_orders` collection stores: `id` (Firestore doc ID), `orderId` (human-readable), `customer`, `item`, `status`, `priority`, `dueDate`, `progress`, `notes`, `updatedAt`

## Common Conventions

**UI Patterns:**
- Error messages: `SnackBar` for actions, `Center(child: Text('Error: ...'))` for page-level errors
- Layouts: `MainLayout` in `lib/layouts/main_layout.dart` provides `Navigation` sidebar; all pages nest within it
- Components in `lib/components/` are reusable widgets (e.g., `WorkshopCard`, `RevenueChart`, `StatCard`)
- Responsive: desktop and mobile both supported; use `Row`/`Column` with `Expanded` for layout

**Models & Serialization:**
- Date handling: Use `Timestamp.toDate()` for Firestore, handle `int` milliseconds as fallback
- All models have `fromMap(id, Map)` and `toJson()` methods; keep them synchronized
- Example: `WorkshopOrder.fromMap()` parses `status` string to enum via `WorkshopStatus.values.firstWhere()`

**Adding New Features:**
1. Create model in `lib/models/` with `fromMap()` and `toJson()`
2. Add DatabaseService methods (typically streams + write/update methods)
3. Create page in `lib/pages/` as `StatefulWidget`; wrap with `MainLayout` and register route in `main.dart`
4. Add navigation entry in `lib/components/navigation.dart`

## Export & Reporting

**PDF/Print Service:**
- `PdfService` in `lib/services/pdf_service.dart` handles receipts (80mm roll) and workshop job tickets (A4)
- Call `printReceipt(context, order)` or `printWorkshopOrder(context, order)` from pages
- Returns platform print dialog; supports preview on mobile/desktop

**CSV Export:**
- `ExportService` in `lib/services/export_service.dart` converts `Order` lists to CSV and shares via system share dialog
- Uses `csv` package and `share_plus` for cross-platform file sharing

## Critical Build & Dependency Info

- **SDK:** Dart 3.10+, Flutter (stable)
- **Key dependencies:** `firebase_core`, `cloud_firestore`, `firebase_auth`, `firebase_storage`, `image_picker`, `pdf`, `printing`, `fl_chart`, `csv`, `shared_preferences`
- **Web-specific:** `universal_html` for web file downloads in export flows
- Build: `flutter pub get && flutter run` (standard); multi-platform CMake in `linux/`, `windows/`, `macos/`

---

**Update this file when adding major domains, external integrations, or architectural patterns.**
