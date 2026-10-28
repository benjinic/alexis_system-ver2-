import 'package:flutter/material.dart';
import '../components/icon_text.dart';
import 'package:intl/intl.dart';
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
                ? '${item.service}: ${AppLocalizations.of(context).fabricMarkedOrdered}'
                : '${item.service}: ${AppLocalizations.of(context).fabricMarkedNotOrdered}',
          ),
        ),
      );
      return allFabricOrdered;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update item fabric status: $e'),
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

  // === 日期範圍選擇 → 細項匯出 ===
  Future<void> _handleExport() async {
    DateTime? fromDate;
    DateTime? toDate;

    final dateFmt = DateFormat('yyyy-MM-dd');
    final cs = Theme.of(context).colorScheme;

    // 1. 先讓用戶選擇日期範圍
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('選擇匯出日期範圍'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.calendar_today, color: cs.primary),
                title: const Text('開始日期'),
                subtitle: Text(
                  fromDate != null ? dateFmt.format(fromDate!) : '不限（全部）',
                  style: TextStyle(
                    color: fromDate != null ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                ),
                trailing: fromDate != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setDlgState(() => fromDate = null),
                      )
                    : null,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: fromDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setDlgState(() => fromDate = picked);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.calendar_month, color: cs.primary),
                title: const Text('結束日期'),
                subtitle: Text(
                  toDate != null ? dateFmt.format(toDate!) : '不限（全部）',
                  style: TextStyle(
                    color: toDate != null ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                ),
                trailing: toDate != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setDlgState(() => toDate = null),
                      )
                    : null,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: toDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setDlgState(() => toDate = picked);
                },
              ),
              if (fromDate != null && toDate != null && toDate!.isBefore(fromDate!))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '結束日期不能早於開始日期',
                    style: TextStyle(color: cs.error, fontSize: 12),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(ctx).cancelButton),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('匯出'),
              onPressed:
                  (fromDate != null && toDate != null && toDate!.isBefore(fromDate!))
                      ? null
                      : () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;

    // 2. 開始匯出
    await _runExport(fromDate: fromDate, toDate: toDate, dateFmt: dateFmt);
  }

  Future<void> _runExport({
    DateTime? fromDate,
    DateTime? toDate,
    required DateFormat dateFmt,
  }) async {
    final progressMsg = ValueNotifier<String>('正在準備...');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => Center(
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ValueListenableBuilder<String>(
              valueListenable: progressMsg,
              builder: (_, msg, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(msg, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      progressMsg.value = '正在載入訂單清單...';
      final allOrders = await _dbService.getOrdersStream(limit: 10000).first;

      // 依日期範圍過濾（toDate 包含當天 23:59:59）
      final toDateEnd = toDate != null
          ? DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59)
          : null;
      final filtered = allOrders.where((o) {
        final d = o.createdAt ?? o.date;
        if (d == null) return fromDate == null && toDate == null;
        if (fromDate != null && d.isBefore(fromDate)) return false;
        if (toDateEnd != null && d.isAfter(toDateEnd)) return false;
        return true;
      }).toList();

      final total = filtered.length;
      final services = await _dbService.getServicesStream().first;
      final serviceByName = {
        for (final service in services) service.name: service,
      };

      List<Order> fullOrders = [];
      for (var i = 0; i < filtered.length; i++) {
        final order = filtered[i];
        progressMsg.value = '正在讀取 ${i + 1} / $total 筆訂單...';
        final items = await _dbService.getOrderItems(order.id);
        final itemsToUse = items.isNotEmpty ? items : order.items;

        final isHistorical =
            order.status.toLowerCase() == 'completed' ||
            order.status.toLowerCase() == 'cancelled' ||
            order.status.toLowerCase() == 'confirmed';
        fullOrders.add(
          isHistorical
              ? order.copyWith(items: itemsToUse)
              : CostCalculationService.syncOrderWithServicePrices(
                  order.copyWith(items: itemsToUse),
                  serviceByName: serviceByName,
                ),
        );
      }

      final csvData = ExportService.generateItemDetailsCSV(fullOrders);

      // 檔名含日期範圍
      final suffix = (fromDate != null || toDate != null)
          ? '_${fromDate != null ? dateFmt.format(fromDate) : 'start'}'
            '_to_${toDate != null ? dateFmt.format(toDate) : 'end'}'
          : '';
      final fileName = 'Alexis_Orders$suffix.csv';

      final bytes = utf8.encode('﻿$csvData');
      final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();
      html.Url.revokeObjectUrl(url);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已匯出 $total 筆訂單　$fileName'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).exportFailedMsg(e))),
        );
      }
    }
  }

  void _showOrderDetails(BuildContext context, Order order) {
    bool dialogFabricOrdered = order.isFabricOrdered;
    String dialogStatus = order.status;

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
                              AppLocalizations.of(context).orderDetails,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Order #${order.id}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
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
                                if (dialogStatus != 'completed' &&
                                    dialogStatus != 'cancelled')
                                  Builder(builder: (ctx) {
                                    final cs = Theme.of(ctx).colorScheme;
                                    return InkWell(
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
                                              ? cs.tertiaryContainer
                                              : cs.errorContainer,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: dialogFabricOrdered
                                                ? cs.tertiary.withValues(alpha: 0.5)
                                                : cs.error.withValues(alpha: 0.5),
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
                                                  ? cs.onTertiaryContainer
                                                  : cs.onErrorContainer,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              dialogFabricOrdered
                                                  ? 'Fabric Ready'
                                                  : 'Mark Fabric Ordered',
                                              style: TextStyle(
                                                color: dialogFabricOrdered
                                                    ? cs.onTertiaryContainer
                                                    : cs.onErrorContainer,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  })
                                else
                                  const SizedBox.shrink(),
                                _buildStatusBadge(dialogStatus),
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
                              AppLocalizations.of(context).dateLabel,
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
                            if (order.deliveryDate != null)
                              _buildDetailRow(
                                Icons.event_outlined,
                                AppLocalizations.of(context).deliveryDateLabel,
                                DateFormat('yyyy-MM-dd').format(order.deliveryDate!),
                              ),
                            if (order.notes.isNotEmpty)
                              _buildDetailRow(
                                Icons.notes_outlined,
                                AppLocalizations.of(context).notesLabel,
                                order.notes,
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
                                          Builder(
                                            builder: (ctx) => Text(
                                              AppLocalizations.of(ctx).internalCostProfit,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Builder(
                                            builder: (ctx) {
                                              final l = AppLocalizations.of(ctx);
                                              final cs = Theme.of(ctx).colorScheme;
                                              return Column(
                                                children: [
                                                  _buildFinancialRow(
                                                    l.materialCost,
                                                    -detailOrder.materialCost,
                                                    isCost: true,
                                                    color: cs.error,
                                                  ),
                                                  _buildFinancialRow(
                                                    l.outsourcingCost,
                                                    -detailOrder.outsourcingCost,
                                                    isCost: true,
                                                    color: cs.error,
                                                  ),
                                                  _buildFinancialRow(
                                                    l.fixedCost,
                                                    -detailOrder.fixedCost,
                                                    isCost: true,
                                                    color: cs.error,
                                                  ),
                                                  if (detailOrder.laborCost > 0)
                                                    _buildFinancialRow(
                                                      l.laborCost,
                                                      -detailOrder.laborCost,
                                                      isCost: true,
                                                      color: cs.error,
                                                    ),
                                                  const Divider(),
                                                  _buildFinancialRow(
                                                    l.totalCost,
                                                    -detailOrder.totalCost,
                                                    isCost: true,
                                                    color: cs.error,
                                                  ),
                                                  _buildFinancialRow(
                                                    l.netProfit,
                                                    totalProfit,
                                                    color: cs.tertiary,
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
                                                    color: cs.tertiary,
                                                  ),
                                                  _buildFinancialRow(
                                                    l.balanceDue,
                                                    detailOrder.balance,
                                                    color: detailOrder.balance > 0
                                                        ? cs.error
                                                        : cs.onSurfaceVariant,
                                                    isBold: detailOrder.balance > 0,
                                                  ),
                                                  if (detailOrder.payments.isNotEmpty) ...[
                                                    const SizedBox(height: 16),
                                                    const Divider(),
                                                    Text(
                                                      l.balancePaymentsLabel,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w600,
                                                        color: cs.onSurfaceVariant,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    ...detailOrder.payments.map(
                                                      (p) => Padding(
                                                        padding: const EdgeInsets.only(bottom: 4),
                                                        child: Row(
                                                          children: [
                                                            Text(
                                                              DateFormat('MM/dd').format(p.paidAt),
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                color: cs.onSurfaceVariant,
                                                              ),
                                                            ),
                                                            const SizedBox(width: 8),
                                                            Text(
                                                              p.method,
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                color: cs.onSurfaceVariant,
                                                              ),
                                                            ),
                                                            const Spacer(),
                                                            Text(
                                                              '\$${p.amount.toStringAsFixed(0)}',
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                fontWeight: FontWeight.w600,
                                                                color: cs.tertiary,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ],
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
                                      child: Card(
                                        margin: EdgeInsets.symmetric(horizontal: 60),
                                        child: Padding(
                                          padding: EdgeInsets.all(28),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              CircularProgressIndicator(),
                                              SizedBox(height: 16),
                                              Text('Loading...'),
                                            ],
                                          ),
                                        ),
                                      ),
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
                                label: Text(AppLocalizations.of(context).editButton),
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
                                      child: Card(
                                        margin: EdgeInsets.symmetric(horizontal: 60),
                                        child: Padding(
                                          padding: EdgeInsets.all(28),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              CircularProgressIndicator(),
                                              SizedBox(height: 16),
                                              Text('Loading...'),
                                            ],
                                          ),
                                        ),
                                      ),
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
                                label: Text(AppLocalizations.of(context).receiptButton),
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
                            label: Text(AppLocalizations.of(context).photosButton),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        if (dialogStatus == 'pending') ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _changeOrderStatus(
                                context: context,
                                order: order.copyWith(status: dialogStatus),
                                newStatus: 'confirmed',
                                setDialogState: setDialogState,
                                onStatusChanged: (s) => dialogStatus = s,
                              ),
                              icon: const IconText(Icons.thumb_up_outlined),
                              label: Text(AppLocalizations.of(context).confirmOrderButton),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Theme.of(context).colorScheme.primary,
                                foregroundColor:
                                    Theme.of(context).colorScheme.onPrimary,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ),
                        ] else if (dialogStatus == 'confirmed') ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _changeOrderStatus(
                                context: context,
                                order: order.copyWith(status: dialogStatus),
                                newStatus: 'completed',
                                setDialogState: setDialogState,
                                onStatusChanged: (s) => dialogStatus = s,
                              ),
                              icon: const IconText(Icons.check_circle_outline),
                              label: Text(AppLocalizations.of(context).markAsCompleteButton),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Theme.of(context).colorScheme.tertiary,
                                foregroundColor:
                                    Theme.of(context).colorScheme.onTertiary,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ),
                        ],
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
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.errorContainer,
                              foregroundColor:
                                  Theme.of(context).colorScheme.error,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .error
                                    .withValues(alpha: 0.3),
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
    final cs = Theme.of(context).colorScheme;
    final fabricStatusColor = !requiresFabric
        ? cs.onSurfaceVariant
        : (item.isFabricOrdered ? cs.tertiary : cs.error);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
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
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconText(
                  Icons.checkroom,
                  color: cs.onPrimaryContainer,
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
                            color: cs.onSurfaceVariant,
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
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 96,
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconText(
            Icons.image_not_supported_outlined,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: 6),
          Text(
            'No fabric image',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildFabricMetaChip(IconData icon, String label) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconText(icon, size: 14, color: cs.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: cs.onSecondaryContainer),
          ),
        ],
      ),
    );
  }

  Future<void> _changeOrderStatus({
    required BuildContext context,
    required Order order,
    required String newStatus,
    required StateSetter setDialogState,
    required void Function(String) onStatusChanged,
  }) async {
    final l10n = AppLocalizations.of(context);
    final label = newStatus == 'confirmed'
        ? l10n.confirmOrderButton
        : l10n.markAsCompleteButton;
    final message = newStatus == 'confirmed'
        ? l10n.confirmOrderMsg
        : l10n.markCompleteMsg;

    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(ctx).cancelButton),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus == 'confirmed'
                  ? Theme.of(ctx).colorScheme.primary
                  : Theme.of(ctx).colorScheme.tertiary,
              foregroundColor: newStatus == 'confirmed'
                  ? Theme.of(ctx).colorScheme.onPrimary
                  : Theme.of(ctx).colorScheme.onTertiary,
            ),
            child: Text(label),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      await _dbService.updateOrderStatus(order.id, newStatus);
      if (!mounted) return;
      setDialogState(() => onStatusChanged(newStatus));
      messenger.showSnackBar(
        SnackBar(
          content: Text('Order #${order.id} → ${newStatus.toUpperCase()}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    }
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
            child: Text(AppLocalizations.of(ctx).cancelButton),
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
                  ),
                );
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Error deleting order: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
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
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).searchOrdersHint,
                prefixIcon: const IconText(Icons.search),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                FilterChip(
                  label: Text(AppLocalizations.of(context).filterAll),
                  selected: !_filterPending && !_filterOutstanding,
                  onSelected: (_) => setState(() {
                    _filterPending = false;
                    _filterOutstanding = false;
                  }),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(AppLocalizations.of(context).pendingOrders),
                  selected: _filterPending,
                  onSelected: (v) => setState(() {
                    _filterPending = v;
                    if (v) _filterOutstanding = false;
                  }),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(AppLocalizations.of(context).outstandingOrders),
                  selected: _filterOutstanding,
                  onSelected: (v) => setState(() {
                    _filterOutstanding = v;
                    if (v) _filterPending = false;
                  }),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Order>>(
              stream: _filterOutstanding
                  ? _dbService.getOrdersStream()  // no limit — scan all to find every balance > 0
                  : _dbService.getOrdersStream(limit: _ordersLimit),
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
                  orders.sort((a, b) => b.balance.compareTo(a.balance));
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
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? AppLocalizations.of(context).noOrdersFound
                              : AppLocalizations.of(context).noMatchingOrders,
                          style: TextStyle(
                            fontSize: 16,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
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

                final totalOutstanding = _filterOutstanding
                    ? orders.fold(0.0, (sum, o) => sum + o.balance)
                    : 0.0;

                return Column(
                  children: [
                    if (_filterOutstanding)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            IconText(
                              Icons.account_balance_wallet_outlined,
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${orders.length} 筆待收款',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Text(
                              '\$${totalOutstanding.toStringAsFixed(0)}',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onErrorContainer,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                        itemCount: orders.length + 1,
                        itemBuilder: (context, index) {
                          if (index == orders.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 20.0,
                              ),
                              child: Center(
                                child: _filterOutstanding ||
                                        orders.length < _ordersLimit
                                    ? Text(
                                        AppLocalizations.of(
                                          context,
                                        ).allOrdersLoaded(orders.length),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      )
                                    : TextButton.icon(
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
                      ),
                    ),
                  ],
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
    final now = DateTime.now();
    final isOverdue = order.deliveryDate != null &&
        order.deliveryDate!.isBefore(now) &&
        syncedOrder.balance > 0;
    final isCompletedUnpaid =
        order.status == 'completed' && syncedOrder.balance > 0;
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      color: isOverdue ? cs.errorContainer.withValues(alpha: 0.25) : null,
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
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '#${order.id}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
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
                          Builder(builder: (ctx) {
                            final cs = Theme.of(ctx).colorScheme;
                            final ordered = order.isFabricOrdered;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: ordered
                                    ? cs.tertiaryContainer
                                    : cs.errorContainer,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: ordered
                                      ? cs.tertiary.withValues(alpha: 0.5)
                                      : cs.error.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconText(
                                    ordered
                                        ? Icons.check_circle_outline
                                        : Icons.warning_amber_rounded,
                                    color: ordered
                                        ? cs.onTertiaryContainer
                                        : cs.onErrorContainer,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    ordered ? 'Fabric Ordered' : 'Pending',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: ordered
                                          ? cs.onTertiaryContainer
                                          : cs.onErrorContainer,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ] else if (isCompletedUnpaid) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: cs.secondary.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconText(
                                  Icons.check_circle_outline,
                                  color: cs.onSecondaryContainer,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Completed · Unpaid',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: cs.onSecondaryContainer,
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
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (order.deliveryDate != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconText(
                                isOverdue
                                    ? Icons.warning_amber_rounded
                                    : Icons.event_outlined,
                                size: 12,
                                color: isOverdue ? cs.error : cs.secondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isOverdue
                                    ? 'Overdue ${DateFormat('MM/dd').format(order.deliveryDate!)}'
                                    : 'Due ${DateFormat('MM/dd').format(order.deliveryDate!)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isOverdue ? cs.error : cs.secondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
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
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 若有欠款，顯示紅色提示
                      if (syncedOrder.balance > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Due: \$${syncedOrder.balance.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                      // 日期顯示
                      Text(
                        order.createdAt != null
                            ? (DateTime.now().difference(order.createdAt!).inDays > 365
                                ? DateFormat('yy/MM/dd').format(order.createdAt!)
                                : DateFormat('MM/dd').format(order.createdAt!))
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
    final cs = Theme.of(context).colorScheme;
    Color color;
    switch (status.toLowerCase()) {
      case 'completed':
        color = cs.tertiary;
        break;
      case 'confirmed':
        color = cs.primary;
        break;
      case 'pending':
        color = cs.secondary;
        break;
      default:
        color = cs.outline;
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
              color: color ??
                  (isCost
                      ? Theme.of(context).colorScheme.error
                      : (isTotal
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ),
        ],
      ),
    );
  }
}
