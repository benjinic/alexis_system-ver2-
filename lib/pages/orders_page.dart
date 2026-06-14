import 'package:flutter/material.dart';
import '../components/icon_text.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'package:universal_html/html.dart' as html;

import '../l10n/app_localizations.dart';
import '../models/material_item.dart';
import '../models/order.dart';
import '../models/service_item.dart';
import '../services/database_service.dart';
import '../services/cost_calculation_service.dart';
import '../services/pdf_service.dart';
import '../services/export_service.dart';
import 'pos_page.dart';
import 'order_images_page.dart';

class OrdersPage extends StatefulWidget {
  final bool showOutstandingOnly;
  final bool showPendingOnly;

  const OrdersPage({
    super.key,
    this.showOutstandingOnly = false,
    this.showPendingOnly = false,
  });

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final DatabaseService _dbService = DatabaseService();
  final PdfService _pdfService = PdfService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _ordersLimit = 20; // Default: load 20 orders for performance
  bool _filterOutstanding = false;
  bool _filterPending = false;
  Map<String, ServiceItem> _serviceByName = {};

  @override
  void initState() {
    super.initState();
    _filterOutstanding = widget.showOutstandingOnly;
    _filterPending = widget.showPendingOnly;

    // 直接監聽 Firebase service 數據流
    _dbService.getServicesStream().listen((services) {
      if (mounted) {
        setState(() {
          _serviceByName = {
            for (final service in services) service.name: service,
          };
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _navigateToPOS() {
    Navigator.of(context).pushReplacementNamed('/pos');
  }

  // Load more historical orders (pagination)
  void _loadMoreOrders() {
    setState(() {
      _ordersLimit += 20; // Load 20 more orders each time
    });
  }

  void _showImageLightbox(BuildContext context, String imageUrl, String title) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.black.withValues(alpha: 0.9),
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(title),
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const IconText(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.network(imageUrl, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _requiresFabric(OrderItem item) {
    return (item.fabricId ?? '').trim().isNotEmpty ||
        (item.fabricName ?? '').trim().isNotEmpty ||
        item.fabricUsed > 0;
  }

  bool _isOrderFabricFullyOrdered(List<OrderItem> items) {
    final fabricItems = items.where(_requiresFabric).toList();
    if (fabricItems.isEmpty) return false;
    return fabricItems.every((item) => item.isFabricOrdered);
  }

  Future<bool?> _toggleFabricOrdered({
    required String orderId,
    required bool currentStatus,
  }) async {
    final nextStatus = !currentStatus;
    try {
      await _dbService.updateOrderFabricRequiredItemsStatus(
        orderId: orderId,
        isFabricOrdered: nextStatus,
      );
      await _dbService.updateWorkshopOrdersFabricStatus(
        orderId: orderId,
        isFabricOrdered: nextStatus,
      );
      if (!mounted) return null;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            !currentStatus
                ? AppLocalizations.of(context).fabricMarkedOrdered
                : AppLocalizations.of(context).fabricMarkedNotOrdered,
          ),
        ),
      );
      return nextStatus;
    } catch (e) {
      if (!mounted) return null;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to update fabric status: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }

  Future<bool?> _toggleOrderItemFabricOrdered({
    required String orderId,
    required OrderItem item,
  }) async {
    final requiresFabric = _requiresFabric(item);
    if (!requiresFabric) return null;

    try {
      await _dbService.updateOrderItemFabricStatus(
        orderId: orderId,
        itemId: item.id,
        isFabricOrdered: !item.isFabricOrdered,
      );

      final latestItems = await _dbService.getOrderItems(orderId);
      final allFabricOrdered = _isOrderFabricFullyOrdered(latestItems);
      await _dbService.updateWorkshopOrdersFabricStatus(
        orderId: orderId,
        isFabricOrdered: allFabricOrdered,
      );

      if (!mounted) return null;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !item.isFabricOrdered
                ? '${item.service}: fabric marked as ordered'
                : '${item.service}: fabric marked as not ordered',
          ),
        ),
      );
      return allFabricOrdered;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update item fabric status: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }

  Future<Order> _buildSyncedFullOrder(
    Order order,
    List<OrderItem> items,
  ) async {
    // 歷史鎖：已完成/取消/已付訂金的訂單保留原始價格，不重算
    final isHistorical =
        order.status.toLowerCase() == 'completed' ||
        order.status.toLowerCase() == 'cancelled' ||
        order.status.toLowerCase() == 'confirmed';
    if (isHistorical) {
      return order.copyWith(items: items);
    }
    final services = await _dbService.getServicesStream().first;
    final serviceByName = {
      for (final service in services) service.name: service,
    };

    return CostCalculationService.syncOrderWithServicePrices(
      order.copyWith(items: items),
      serviceByName: serviceByName,
    );
  }

  // === 細項匯出邏輯 ===
  Future<void> _handleExport() async {
    // 1. 顯示 Loading 畫面 (抓取大量細項需要一點時間)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 2. 先抓取所有的「訂單主檔」
      final allOrders = await _dbService.getOrdersStream(limit: 10000).first;
      final services = await _dbService.getServicesStream().first;
      final serviceByName = {
        for (final service in services) service.name: service,
      };

      // 3. 【關鍵修復】逐一抓取每個訂單的「商品細項」，並組合成完整的訂單
      List<Order> fullOrders = [];
      for (var order in allOrders) {
        // 去 order_items 集合中把這筆訂單的商品抓出來
        final items = await _dbService.getOrderItems(order.id);
        final itemsToUse = items.isNotEmpty ? items : order.items;

        // 歷史鎖：已完成/取消/已付訂金的訂單保留原始價格
        final isHistorical =
            order.status.toLowerCase() == 'completed' ||
            order.status.toLowerCase() == 'cancelled' ||
            order.status.toLowerCase() == 'confirmed';
        if (isHistorical) {
          fullOrders.add(order.copyWith(items: itemsToUse));
        } else {
          fullOrders.add(
            CostCalculationService.syncOrderWithServicePrices(
              order.copyWith(items: itemsToUse),
              serviceByName: serviceByName,
            ),
          );
        }
      }

      // 4. 呼叫我們寫好的 Service 產生單項明細 CSV
      final csvData = ExportService.generateItemDetailsCSV(fullOrders);

      // 5. 觸發網頁下載
      final bytes = utf8.encode('\uFEFF$csvData'); // \uFEFF 是為了防止 Excel 中文亂碼
      final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
      final url = html.Url.createObjectUrlFromBlob(blob);

      html.AnchorElement(href: url)
        ..setAttribute('download', 'Alexis_Item_Details.csv')
        ..click();

      html.Url.revokeObjectUrl(url);

      // 6. 成功後，關閉 Loading 並顯示成功訊息
      if (mounted) {
        Navigator.pop(context); // 關閉 Loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 匯出成功！'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // 7. 失敗處理
      if (mounted) {
        Navigator.pop(context); // 關閉 Loading

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 匯出失敗: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showOrderDetails(BuildContext context, Order order) {
    bool dialogFabricOrdered = order.isFabricOrdered;

    // 改用 showDialog (中間彈出)
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) => Dialog(
            // 圓角
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            // 限制最大寬度 (在電腦版不會太寬)，高度自適應螢幕
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 500,
                maxHeight: MediaQuery.sizeOf(context).height * 0.88,
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize:
                      MainAxisSize.max, // 撐滿 ConstrainedBox 高度，確保底部按鈕不被截斷
                  children: [
                    // --- Header ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Order Details',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Order #${order.id}',
                              style: TextStyle(
                                color: Theme.of(context).primaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        // 關閉按鈕 (X)
                        IconButton(
                          icon: const IconText(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    // --- Scrollable Content ---
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                if (order.status != 'completed' &&
                                    order.status != 'cancelled')
                                  InkWell(
                                    onTap: () async {
                                      final updatedStatus =
                                          await _toggleFabricOrdered(
                                            orderId: order.id,
                                            currentStatus: dialogFabricOrdered,
                                          );
                                      if (updatedStatus != null &&
                                          context.mounted) {
                                        setDialogState(() {
                                          dialogFabricOrdered = updatedStatus;
                                        });
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: dialogFabricOrdered
                                            ? Colors.green[50]
                                            : Colors.red[50],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: dialogFabricOrdered
                                              ? Colors.green[300]!
                                              : Colors.red[300]!,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconText(
                                            dialogFabricOrdered
                                                ? Icons.inventory_2
                                                : Icons.shopping_cart_checkout,
                                            color: dialogFabricOrdered
                                                ? Colors.green[700]
                                                : Colors.red[700],
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            dialogFabricOrdered
                                                ? 'Fabric Ready'
                                                : 'Mark Fabric Ordered',
                                            style: TextStyle(
                                              color: dialogFabricOrdered
                                                  ? Colors.green[700]
                                                  : Colors.red[700],
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                else
                                  const SizedBox.shrink(),
                                _buildStatusBadge(order.status),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // 客戶與日期
                            _buildDetailRow(
                              Icons.person,
                              AppLocalizations.of(context).customerLabel,
                              order.customerName,
                            ),
                            _buildDetailRow(
                              Icons.calendar_today,
                              'Date',
                              order.createdAt != null
                                  ? DateFormat(
                                      'yyyy-MM-dd HH:mm',
                                    ).format(order.createdAt!)
                                  : 'N/A',
                            ),
                            _buildDetailRow(
                              Icons.payment,
                              AppLocalizations.of(context).paymentLabel,
                              order.paymentMethod,
                            ),
                            const SizedBox(height: 24),
                            Text(
                              AppLocalizations.of(context).itemsLabel,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            // 異步載入商品
                            FutureBuilder<List<OrderItem>>(
                              future: _dbService.getOrderItems(order.id),
                              builder: (context, snapshot) {
                                final items =
                                    (snapshot.data != null &&
                                        snapshot.data!.isNotEmpty)
                                    ? snapshot.data!
                                    : order.items;
                                final isHistorical =
                                    order.status.toLowerCase() == 'completed' ||
                                    order.status.toLowerCase() == 'cancelled' ||
                                    order.status.toLowerCase() == 'confirmed';
                                final detailOrder = isHistorical
                                    ? order.copyWith(items: items)
                                    : CostCalculationService.syncOrderWithServicePrices(
                                        order.copyWith(items: items),
                                        serviceByName: _serviceByName,
                                      );
                                final allFabricOrdered =
                                    _isOrderFabricFullyOrdered(items);
                                if (allFabricOrdered != dialogFabricOrdered) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (!context.mounted) return;
                                    setDialogState(() {
                                      dialogFabricOrdered = allFabricOrdered;
                                    });
                                  });

                                  // Keep order-level flag aligned for lists/filters that still rely on it.
                                  unawaited(
                                    _dbService.updateOrderFabricStatus(
                                      orderId: order.id,
                                      isFabricOrdered: allFabricOrdered,
                                    ),
                                  );
                                }
                                final totalProfit =
                                    detailOrder.total - detailOrder.totalCost;
                                if (snapshot.connectionState ==
                                        ConnectionState.waiting &&
                                    snapshot.data == null) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children:
                                      items
                                          .map<Widget>(
                                            (item) => _buildOrderItemDetailCard(
                                              orderId: order.id,
                                              item: item,
                                              onFabricStatusChanged: (updated) {
                                                if (!context.mounted) return;
                                                setDialogState(() {
                                                  dialogFabricOrdered = updated;
                                                });
                                              },
                                            ),
                                          )
                                          .toList()
                                        ..addAll([
                                          const Divider(height: 24),
                                          const Text(
                                            'Internal Cost & Profit',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Builder(
                                            builder: (ctx) {
                                              final l = AppLocalizations.of(
                                                ctx,
                                              );
                                              return Column(
                                                children: [
                                                  _buildFinancialRow(
                                                    l.materialCost,
                                                    -detailOrder.materialCost,
                                                    isCost: true,
                                                    color: Colors.red[300],
                                                  ),
                                                  _buildFinancialRow(
                                                    l.outsourcingCost,
                                                    -detailOrder
                                                        .outsourcingCost,
                                                    isCost: true,
                                                    color: Colors.red[300],
                                                  ),
                                                  _buildFinancialRow(
                                                    l.fixedCost,
                                                    -detailOrder.fixedCost,
                                                    isCost: true,
                                                    color: Colors.red[300],
                                                  ),
                                                  const Divider(),
                                                  _buildFinancialRow(
                                                    l.totalCost,
                                                    -detailOrder.totalCost,
                                                    isCost: true,
                                                    color: Colors.red[300],
                                                  ),
                                                  _buildFinancialRow(
                                                    l.netProfit,
                                                    totalProfit,
                                                    color: Colors.green[700],
                                                    isBold: true,
                                                  ),
                                                  const Divider(height: 32),
                                                  _buildFinancialRow(
                                                    l.subtotal,
                                                    detailOrder.subtotal,
                                                  ),
                                                  if (detailOrder.discount > 0)
                                                    _buildFinancialRow(
                                                      l.discount,
                                                      -detailOrder.discount,
                                                      isCost: true,
                                                    ),
                                                  const Divider(),
                                                  _buildFinancialRow(
                                                    l.total,
                                                    detailOrder.total,
                                                    isTotal: true,
                                                  ),
                                                  const SizedBox(height: 16),
                                                  _buildFinancialRow(
                                                    l.depositPaid,
                                                    detailOrder.deposit,
                                                    color: Colors.green,
                                                  ),
                                                  _buildFinancialRow(
                                                    l.balanceDue,
                                                    detailOrder.balance,
                                                    color:
                                                        detailOrder.balance > 0
                                                        ? Colors.red
                                                        : Colors.grey,
                                                    isBold:
                                                        detailOrder.balance > 0,
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                        ]),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // --- Footer Actions (按鈕區) ---
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  // 編輯邏輯 (先抓資料再跳轉)
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (c) => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                  try {
                                    final itemsFromDb = await _dbService
                                        .getOrderItems(order.id);
                                    final itemsToUse = itemsFromDb.isNotEmpty
                                        ? itemsFromDb
                                        : order.items;
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                    } // 關閉 Loading

                                    final fullOrder =
                                        await _buildSyncedFullOrder(
                                          order,
                                          itemsToUse,
                                        );

                                    if (context.mounted) {
                                      Navigator.pop(context); // 關閉 Dialog
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              POSPage(orderForEdit: fullOrder),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text('Error: $e')),
                                      );
                                    }
                                  }
                                },
                                icon: const IconText(Icons.edit),
                                label: const Text('Edit'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // === 修改重點：Print Button ===
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  // 1. 顯示讀取中 (Loading)
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (c) => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );

                                  try {
                                    // 2. 去資料庫抓取完整的商品細項
                                    final items = await _dbService
                                        .getOrderItems(order.id);

                                    // 3. 關閉 Loading
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                    }

                                    // 4. 組合完整訂單 (補上 items 並重算成本欄位)
                                    final fullOrder =
                                        await _buildSyncedFullOrder(
                                          order,
                                          items,
                                        );

                                    // 5. 呼叫列印服務
                                    if (context.mounted) {
                                      await _pdfService.printReceipt(
                                        context,
                                        fullOrder,
                                      );
                                    }
                                  } catch (e) {
                                    // 錯誤處理
                                    if (context.mounted) {
                                      Navigator.pop(context); // 關閉 Loading
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text('Error printing: $e'),
                                        ),
                                      );
                                    }
                                  }
                                },
                                icon: const IconText(Icons.print),
                                label: const Text('Receipt'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Photos button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => OrderImagesPage(
                                    orderId: order.id,
                                    orderLabel:
                                        'Order #${order.id} — ${order.customerName}',
                                  ),
                                ),
                              );
                            },
                            icon: const IconText(Icons.photo_library_outlined),
                            label: const Text('Photos'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _confirmDelete(context, order),
                            icon: const IconText(Icons.delete_forever),
                            label: Text(
                              AppLocalizations.of(context).deleteOrder,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red[50],
                              foregroundColor: Colors.red,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(
                                color: Colors.red.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrderItemDetailCard({
    required String orderId,
    required OrderItem item,
    required ValueChanged<bool> onFabricStatusChanged,
  }) {
    final requiresFabric = _requiresFabric(item);
    final fabricStatusLabel = !requiresFabric
        ? 'No Fabric Required'
        : (item.isFabricOrdered ? 'Fabric Ordered' : 'Pending Order');
    final fabricStatusColor = !requiresFabric
        ? Colors.blueGrey
        : (item.isFabricOrdered ? Colors.green : Colors.orange);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconText(
                  Icons.checkroom,
                  color: Colors.blue[800],
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.service,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (item.fabricName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Fabric: ${item.fabricName} (${item.fabricUsed}m)',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: requiresFabric
                          ? () async {
                              final updated =
                                  await _toggleOrderItemFabricOrdered(
                                    orderId: orderId,
                                    item: item,
                                  );
                              if (updated != null) {
                                onFabricStatusChanged(updated);
                              }
                            }
                          : null,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: fabricStatusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: fabricStatusColor.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconText(
                              !requiresFabric
                                  ? Icons.inventory_2_outlined
                                  : (item.isFabricOrdered
                                        ? Icons.check_circle
                                        : Icons.local_shipping_outlined),
                              size: 14,
                              color: fabricStatusColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              fabricStatusLabel,
                              style: TextStyle(
                                fontSize: 12,
                                color: fabricStatusColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '\$${CostCalculationService.resolveUnitPrice(item, serviceByName: _serviceByName).toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if ((item.fabricId ?? '').isNotEmpty ||
              (item.fabricName ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            FutureBuilder<MaterialItem?>(
              future: (item.fabricId ?? '').isEmpty
                  ? Future.value(null)
                  : _dbService.getMaterialById(item.fabricId!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    (item.fabricId ?? '').isNotEmpty) {
                  return const LinearProgressIndicator(minHeight: 2);
                }
                return _buildFabricInfoCard(item, snapshot.data);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFabricInfoCard(OrderItem item, MaterialItem? material) {
    final imageUrl = material?.imageUrl;
    final hasImage = imageUrl != null && imageUrl.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasImage)
            GestureDetector(
              onTap: () => _showImageLightbox(
                context,
                imageUrl,
                material?.name ?? item.fabricName ?? 'Fabric Image',
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  imageUrl,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return _buildFabricImageFallback();
                  },
                ),
              ),
            )
          else
            _buildFabricImageFallback(),
          const SizedBox(height: 10),
          Text(
            material?.name ?? item.fabricName ?? 'Fabric details unavailable',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFabricMetaChip(
                Icons.straighten,
                '${item.fabricUsed.toStringAsFixed(1)}m used',
              ),
              if ((item.fabricId ?? '').isNotEmpty)
                _buildFabricMetaChip(Icons.qr_code_2, item.fabricId!),
              if (material != null)
                _buildFabricMetaChip(Icons.sell_outlined, material.category),
              if (material != null)
                _buildFabricMetaChip(
                  Icons.attach_money,
                  'Cost \$${material.costPerUnit.toStringAsFixed(0)}/${material.unit}',
                ),
              if (material != null)
                _buildFabricMetaChip(
                  Icons.inventory_2_outlined,
                  'Stock ${material.stock.toStringAsFixed(1)} ${material.unit}',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFabricImageFallback() {
    return Container(
      height: 96,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.blueGrey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconText(
            Icons.image_not_supported_outlined,
            color: Colors.blueGrey[300],
          ),
          const SizedBox(height: 6),
          Text(
            'No fabric image',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildFabricMetaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blueGrey[50],
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconText(icon, size: 14, color: Colors.blueGrey[700]),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.blueGrey[700]),
          ),
        ],
      ),
    );
  }

  // Confirmation dialog for order deletion
  void _confirmDelete(BuildContext context, Order order) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).deleteOrderConfirm),
        content: Text(
          '${AppLocalizations.of(context).deleteOrderWarning} #${order.id}?\n\n${AppLocalizations.of(context).cannotUndo}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              Navigator.pop(context);

              try {
                await _dbService.deleteOrder(order.id);

                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Order deleted successfully'),
                    backgroundColor: Colors.grey,
                  ),
                );
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Error deleting order: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _filterPending
              ? AppLocalizations.of(context).pendingOrders
              : _filterOutstanding
              ? AppLocalizations.of(context).outstandingOrders
              : AppLocalizations.of(context).ordersTitle,
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const IconText(Icons.download),
            tooltip: AppLocalizations.of(context).exportCSV,
            onPressed: _handleExport,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToPOS,
        icon: const IconText(Icons.add),
        label: Text(AppLocalizations.of(context).newOrder.toUpperCase()),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.black),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).searchOrdersHint,
                hintStyle: TextStyle(color: Colors.grey[600]),
                prefixIcon: const IconText(Icons.search),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 16,
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Order>>(
              stream: _dbService.getOrdersStream(limit: _ordersLimit),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allOrders = snapshot.data ?? [];
                var orders = allOrders.where((order) {
                  final matchesName = order.customerName.toLowerCase().contains(
                    _searchQuery,
                  );
                  // Support searching by order ID
                  final matchesId = order.id.toLowerCase().contains(
                    _searchQuery,
                  );
                  // Support searching by fabric name
                  final matchesFabric = order.fabricSummary
                      .toLowerCase()
                      .contains(_searchQuery);
                  // Support searching by service/item name
                  final matchesItem = order.itemSummary.toLowerCase().contains(
                    _searchQuery,
                  );
                  return matchesName ||
                      matchesId ||
                      matchesFabric ||
                      matchesItem;
                }).toList();

                // 篩選待處理訂單
                if (_filterPending) {
                  orders = orders
                      .where(
                        (o) =>
                            o.status != 'completed' && o.status != 'cancelled',
                      )
                      .toList();
                }
                // 篩選尚欠款項的訂單
                else if (_filterOutstanding) {
                  orders = orders.where((o) => o.balance > 0).toList();
                }

                if (orders.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconText(
                          _searchQuery.isEmpty
                              ? Icons.receipt_long_outlined
                              : Icons.search_off,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? AppLocalizations.of(context).noOrdersFound
                              : AppLocalizations.of(context).noMatchingOrders,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[500],
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (_searchQuery.isEmpty)
                          OutlinedButton.icon(
                            onPressed: _navigateToPOS,
                            icon: const IconText(Icons.add),
                            label: Text(
                              AppLocalizations.of(
                                context,
                              ).createFirstOrder.toUpperCase(),
                            ),
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: _loadMoreOrders,
                            icon: const IconText(Icons.history),
                            label: Text(
                              AppLocalizations.of(context).loadMoreHistory,
                            ),
                          ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  // Add 1 extra item for load more button at bottom
                  itemCount: orders.length + 1,
                  itemBuilder: (context, index) {
                    if (index == orders.length) {
                      // Load More button at bottom
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20.0),
                        child: Center(
                          child: TextButton.icon(
                            onPressed: _loadMoreOrders,
                            icon: const IconText(Icons.expand_more),
                            label: Text(
                              AppLocalizations.of(
                                context,
                              ).loadMoreShowing(_ordersLimit),
                            ),
                          ),
                        ),
                      );
                    }
                    return _buildOrderCard(context, orders[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // === 核心修改：在卡片顯示 Order ID ===
  Widget _buildOrderCard(BuildContext context, Order order) {
    final isHistorical =
        order.status.toLowerCase() == 'completed' ||
        order.status.toLowerCase() == 'cancelled' ||
        order.status.toLowerCase() == 'confirmed';
    final syncedOrder = isHistorical
        ? order
        : (order.items.isNotEmpty
              ? CostCalculationService.syncOrderWithServicePrices(
                  order,
                  serviceByName: _serviceByName,
                )
              : order);
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showOrderDetails(context, order),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start, // 對齊頂部
                children: [
                  // 左側：ID 與 姓名
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 新增：訂單編號顯示
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '#${order.id}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          order.customerName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (order.status != 'completed' &&
                            order.status != 'cancelled') ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: order.isFabricOrdered
                                  ? Colors.green[50]
                                  : Colors.red[50],
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: order.isFabricOrdered
                                    ? Colors.green[200]!
                                    : Colors.red[200]!,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconText(
                                  order.isFabricOrdered
                                      ? Icons.check_circle_outline
                                      : Icons.warning_amber_rounded,
                                  color: order.isFabricOrdered
                                      ? Colors.green[700]
                                      : Colors.red[700],
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  order.isFabricOrdered
                                      ? 'Fabric Ordered'
                                      : 'Pending',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: order.isFabricOrdered
                                        ? Colors.green[700]
                                        : Colors.red[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          order.items.isNotEmpty
                              ? '${order.items.length} items (${order.items.first.service}...)'
                              : 'No items',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 右側：金額與狀態
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$${syncedOrder.total.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 若有欠款，顯示紅色提示
                      if (syncedOrder.balance > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Due: \$${syncedOrder.balance.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                      // 日期顯示
                      Text(
                        order.createdAt != null
                            ? DateFormat('MM/dd').format(order.createdAt!)
                            : '',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 底部狀態條
              Align(
                alignment: Alignment.centerRight,
                child: _buildStatusBadge(order.status),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    switch (status.toLowerCase()) {
      case 'completed':
        color = Colors.green;
        break;
      case 'confirmed':
        color = Colors.blue;
        break;
      case 'pending':
        color = Colors.orange;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          IconText(
            icon,
            size: 16,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialRow(
    String label,
    double amount, {
    bool isTotal = false,
    bool isCost = false,
    Color? color,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold || isTotal
                  ? FontWeight.bold
                  : FontWeight.normal,
              fontSize: isTotal ? 16 : 14,
              color: color,
            ),
          ),
          Text(
            '\$${amount.abs().toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: isBold || isTotal
                  ? FontWeight.bold
                  : FontWeight.normal,
              fontSize: isTotal ? 16 : 14,
              color:
                  color ??
                  (isCost
                      ? Colors.red[300]
                      : (isTotal ? Colors.black : Colors.grey[800])),
            ),
          ),
        ],
      ),
    );
  }
}
