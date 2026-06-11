import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/material_item.dart';
import '../models/order.dart';
import '../services/database_service.dart';
import '../services/pdf_service.dart';
import '../services/export_service.dart';
import 'order_images_page.dart';
import 'pos_page.dart';

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
  final ExportService _exportService = ExportService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _ordersLimit = 20; // Default: load 20 orders for performance
  bool _filterOutstanding = false;
  bool _filterPending = false;

  @override
  void initState() {
    super.initState();
    _filterOutstanding = widget.showOutstandingOnly;
    _filterPending = widget.showPendingOnly;
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
                icon: const Icon(Icons.close, color: Colors.white),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(nextStatus ? '布料已標記為已訂購' : '布料標記為未訂購')),
      );
      return nextStatus;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update fabric status: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }

  // === 修正後的匯出邏輯 ===
  Future<void> _handleExport() async {
    // 1. 顯示 Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 2. 抓取所有訂單
      final allOrders = await _dbService.getOrdersStream(limit: 10000).first;

      // 3. 執行匯出 (注意：這時候 Loading 還在轉)
      // 我們把 export 放在 pop 之前，這樣如果出錯，catch 區塊可以正確關閉 Loading
      await _exportService.exportOrdersToCsv(allOrders);

      // 4. 成功後，關閉 Loading
      if (mounted) Navigator.pop(context);
    } catch (e) {
      // 5. 失敗處理
      if (mounted) {
        // 因為 try 裡面還沒 pop，所以這裡 pop 是正確的 (關閉 Loading)
        Navigator.pop(context);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showOrderDetails(BuildContext context, Order order) {
    // 改用 showDialog (中間彈出)
    showDialog(
      context: context,
      builder: (context) {
        // 使用 AlertDialog 或 Dialog
        return Dialog(
          // 圓角
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          // 限制最大寬度 (在電腦版不會太寬)
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 800),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                // 改用 Column 包裹，避免高度無限延伸
                mainAxisSize: MainAxisSize.min, // 高度自適應
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
                        icon: const Icon(Icons.close),
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
                          // 狀態標籤
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (order.status != 'completed' &&
                                  order.status != 'cancelled')
                                _buildFabricStatusChip(
                                  isFabricOrdered: order.isFabricOrdered,
                                  onTap: () => _toggleFabricOrdered(
                                    orderId: order.id,
                                    currentStatus: order.isFabricOrdered,
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
                            'Customer',
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
                            'Payment',
                            order.paymentMethod,
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Items',
                            style: TextStyle(
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
                                children: items.map(_buildOrderItemCard).toList(),
                              );
                            },
                          ),
                          const Divider(height: 32),
                          // 金額計算
                          _buildFinancialRow('Subtotal', order.subtotal),
                          if (order.discount > 0)
                            _buildFinancialRow(
                              'Discount',
                              -order.discount,
                              isCost: true,
                            ),
                          const Divider(),
                          _buildFinancialRow(
                            'Total',
                            order.total,
                            isTotal: true,
                          ),
                          const SizedBox(height: 16),
                          _buildFinancialRow(
                            'Deposit / Paid',
                            order.deposit,
                            color: Colors.green,
                          ),
                          _buildFinancialRow(
                            'Balance Due',
                            order.balance,
                            color: order.balance > 0 ? Colors.red : Colors.grey,
                            isBold: order.balance > 0,
                          ),
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
                          _buildFinancialRow(
                            'Total Cost',
                            -order.totalCost,
                            isCost: true,
                            color: Colors.red[300],
                          ),
                          _buildFinancialRow(
                            'Net Profit',
                            order.totalProfit,
                            color: Colors.green[700],
                            isBold: true,
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
                                  final items = await _dbService.getOrderItems(
                                    order.id,
                                  );
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                  } // 關閉 Loading

                                  final fullOrder = Order(
                                    id: order.id,
                                    uniqueId: order.uniqueId,
                                    customerId: order.customerId,
                                    customerName: order.customerName,
                                    items: items, // 填入細項
                                    subtotal: order.subtotal,
                                    discount: order.discount,
                                    total: order.total,
                                    deposit: order.deposit,
                                    balancePayment: order.balancePayment,
                                    balancePaymentMethod:
                                        order.balancePaymentMethod,
                                    balancePaidDate: order.balancePaidDate,
                                    balance: order.balance,
                                    totalCost: order.totalCost,
                                    totalProfit: order.totalProfit,
                                    status: order.status,
                                    paymentMethod: order.paymentMethod,
                                    createdAt: order.createdAt,
                                    updatedAt: order.updatedAt,
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
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error: $e')),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.edit),
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
                                  final items = await _dbService.getOrderItems(
                                    order.id,
                                  );

                                  // 3. 關閉 Loading
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                  }

                                  // 4. 組合完整訂單 (補上 items)
                                  final fullOrder = Order(
                                    id: order.id,
                                    uniqueId: order.uniqueId,
                                    customerId: order.customerId,
                                    customerName: order.customerName,
                                    items: items,
                                    // <--- 填入抓到的細項，這樣列印才會有東西！
                                    subtotal: order.subtotal,
                                    discount: order.discount,
                                    total: order.total,
                                    deposit: order.deposit,
                                    balancePayment: order.balancePayment,
                                    balancePaymentMethod:
                                        order.balancePaymentMethod,
                                    balancePaidDate: order.balancePaidDate,
                                    balance: order.balance,
                                    totalCost: order.totalCost,
                                    totalProfit: order.totalProfit,
                                    status: order.status,
                                    paymentMethod: order.paymentMethod,
                                    createdAt: order.createdAt,
                                    updatedAt: order.updatedAt,
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
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Error printing: $e'),
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.print),
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
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderImagesPage(
                                  orderId: order.id,
                                  orderLabel: 'Order #${order.id}',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.photo_library_outlined),
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
                          icon: const Icon(Icons.delete_forever),
                          label: const Text('Delete Order'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[50],
                            foregroundColor: Colors.red,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(
                              color: Colors.red.withOpacity(0.3),
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
        );
      },
    );
  }

  // Confirmation dialog for order deletion
  void _confirmDelete(BuildContext context, Order order) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Order?'),
        content: Text(
          'Are you sure you want to delete Order #${order.id}?\n\nThis action cannot be undone and will deduct the amount from the customer\'s history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              Navigator.pop(context);

              try {
                await _dbService.deleteOrder(order.id);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Order deleted successfully'),
                      backgroundColor: Colors.grey,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error deleting order: \$e'),
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
              ? 'Pending Orders'
              : _filterOutstanding
              ? 'Outstanding Orders'
              : 'Order History',
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export to CSV',
            onPressed: _handleExport,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToPOS,
        icon: const Icon(Icons.add),
        label: const Text('New Order'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
              decoration: InputDecoration(
                hintText: 'Search order #ID or customer...',
                prefixIcon: const Icon(Icons.search),
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
                  return matchesName || matchesId;
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
                        Icon(
                          _searchQuery.isEmpty
                              ? Icons.receipt_long_outlined
                              : Icons.search_off,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? 'No orders found'
                              : 'No matching orders in loaded history',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[500],
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (_searchQuery.isEmpty)
                          OutlinedButton.icon(
                            onPressed: _navigateToPOS,
                            icon: const Icon(Icons.add),
                            label: const Text('Create First Order'),
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: _loadMoreOrders,
                            icon: const Icon(Icons.history),
                            label: const Text('Load More History'),
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
                            icon: const Icon(Icons.expand_more),
                            label: Text('Load More (Showing $_ordersLimit+)'),
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
                        const SizedBox(height: 4),
                        if (order.status != 'completed' &&
                            order.status != 'cancelled') ...[
                          _buildFabricStatusChip(
                            isFabricOrdered: order.isFabricOrdered,
                            compact: true,
                          ),
                          const SizedBox(height: 8),
                        ],
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
                        '\$${order.total.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 若有欠款，顯示紅色提示
                      if (order.balance > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Due: \$${order.balance.toStringAsFixed(0)}',
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
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
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

  Future<MaterialItem?> _loadMaterialForItem(OrderItem item) async {
    final fabricId = item.fabricId?.trim() ?? '';
    if (fabricId.isNotEmpty) {
      return _dbService.getMaterialById(fabricId);
    }

    final fabricName = item.fabricName?.trim().toLowerCase() ?? '';
    if (fabricName.isEmpty) return null;

    final materials = await _dbService.getInventory();
    for (final material in materials) {
      if (material.name.trim().toLowerCase() == fabricName) {
        return material;
      }
    }
    return null;
  }

  Widget _buildOrderItemCard(OrderItem item) {
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
                child: Icon(
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
                  ],
                ),
              ),
              Text(
                '\$${item.price.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (_requiresFabric(item)) ...[
            const SizedBox(height: 10),
            FutureBuilder<MaterialItem?>(
              future: _loadMaterialForItem(item),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
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
    final imageUrl = material?.imageUrl?.trim();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

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
              if ((item.fabricId ?? '').trim().isNotEmpty)
                _buildFabricMetaChip(Icons.qr_code_2, item.fabricId!.trim()),
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
          Icon(
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
          Icon(icon, size: 14, color: Colors.blueGrey[700]),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.blueGrey[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildFabricStatusChip({
    required bool isFabricOrdered,
    bool enabled = true,
    bool compact = false,
    VoidCallback? onTap,
  }) {
    final color = !enabled
        ? Colors.blueGrey
        : (isFabricOrdered ? Colors.green : Colors.orange);
    final label = !enabled
        ? 'No Fabric Required'
        : (isFabricOrdered ? 'Fabric Ordered' : 'Pending Fabric');
    final icon = !enabled
        ? Icons.inventory_2_outlined
        : (isFabricOrdered
              ? Icons.check_circle_outline
              : Icons.local_shipping_outlined);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 13 : 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: compact ? 10 : 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
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
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: Colors.grey)),
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
