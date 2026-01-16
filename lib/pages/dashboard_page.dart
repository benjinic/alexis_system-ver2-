import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../components/stat_card.dart';
import '../components/revenue_chart.dart';
import '../services/database_service.dart';
import '../models/order.dart';
import '../models/customer.dart';
import '../models/workshop_order.dart' as models;
import '../models/workshop_status.dart';
import 'orders_page.dart';
import 'workshop_page.dart';
import '../screens/customers_screen.dart';
import 'cost_analysis_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // 營收篩選狀態
  String _revenueFilterMode = 'Month'; // Options: Week, Month, Year, Custom
  DateTimeRange? _customDateRange;

  // 選擇自訂日期範圍
  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customDateRange,
    );
    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _revenueFilterMode = 'Custom';
      });
    }
  }

  // 共用：取得當前篩選器的日期範圍
  DateTimeRange _getDateRange() {
    final now = DateTime.now();
    DateTime start, end;

    // 設定截止時間為當天的最後一秒
    end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (_revenueFilterMode) {
      case 'Week':
        start = now.subtract(Duration(days: now.weekday - 1));
        start = DateTime(start.year, start.month, start.day);
        break;
      case 'Month':
        start = DateTime(now.year, now.month, 1);
        break;
      case 'Year':
        start = DateTime(now.year, 1, 1);
        break;
      case 'Custom':
        if (_customDateRange != null) {
          start = _customDateRange!.start;
          end = _customDateRange!.end.add(
            const Duration(hours: 23, minutes: 59, seconds: 59),
          );
        } else {
          start = DateTime(now.year, now.month, now.day);
        }
        break;
      default:
        start = DateTime(now.year, now.month, 1);
    }
    return DateTimeRange(start: start, end: end);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard'), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Text(
              'Overview',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Here is what\'s happening in your shop.',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),

            // === Bento Grid Layout ===
            LayoutBuilder(
              builder: (context, constraints) {
                return _buildBentoGrid(constraints);
              },
            ),
            
            const SizedBox(height: 32),

            // Revenue Chart
            Container(
              margin: const EdgeInsets.only(bottom: 32),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1a000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const RevenueChart(),
            ),

            // Recent Orders and Quick Actions
            LayoutBuilder(
              builder: (context, constraints) {
                return StreamBuilder<List<Order>>(
                  stream: DatabaseService().getRecentOrdersStream(limit: 5),
                  builder: (context, snapshot) {
                    final recentOrders = snapshot.data ?? [];

                    if (constraints.maxWidth > 900) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: _buildRecentOrdersList(
                              context,
                              recentOrders,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(flex: 1, child: _buildQuickActions(context)),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          _buildRecentOrdersList(context, recentOrders),
                          const SizedBox(height: 24),
                          _buildQuickActions(context),
                        ],
                      );
                    }
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // === Bento Grid 核心佈局邏輯 ===
  Widget _buildBentoGrid(BoxConstraints constraints) {
    final isDesktop = constraints.maxWidth > 900;

    // 手機版：垂直排列
    if (!isDesktop) {
      return Column(
        children: [
          SizedBox(height: 200, child: _buildDynamicRevenueCard(isBento: true)),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.1, // 調整比例以適應手機
            children: [
              _buildTopServiceCard(isBento: true),
              _buildWorkshopStatusCard(isBento: true),
              _buildOutstandingBalanceCard(isBento: true),
              _buildCustomerGrowthCard(isBento: true),
            ],
          ),
        ],
      );
    }

    // 桌面版：Bento 拼圖佈局
    return SizedBox(
      height: 420,
      child: Row(
        children: [
          // 左欄：核心營收 (40%) - 深色主題
          Expanded(
            flex: 4,
            child: _buildDynamicRevenueCard(isBento: true),
          ),
          const SizedBox(width: 24),

          // 中欄：營運重點 (30%)
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Expanded(child: _buildTopServiceCard(isBento: true)), // 人氣商品 (高亮)
                const SizedBox(height: 24),
                Expanded(child: _buildWorkshopStatusCard(isBento: true)), // 工廠狀態
              ],
            ),
          ),
          const SizedBox(width: 24),

          // 右欄：財務與客戶 (30%)
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Expanded(child: _buildOutstandingBalanceCard(isBento: true)), // 欠款
                const SizedBox(height: 24),
                Expanded(child: _buildCustomerGrowthCard(isBento: true)), // 客戶
              ],
            ),
          ),
        ],
      ),
    );
  }

  // === 1. 動態營收卡片 (支援 Bento 樣式) ===
  Widget _buildDynamicRevenueCard({bool isBento = false}) {
    final range = _getDateRange();
    final start = range.start;
    final end = range.end;
    
    String label;
    if (_revenueFilterMode == 'Custom' && _customDateRange != null) {
       label = '${DateFormat('MM/dd').format(start)} - ${DateFormat('MM/dd').format(end)}';
    } else {
       label = 'This $_revenueFilterMode';
    }

    return StreamBuilder<List<Order>>(
      stream: DatabaseService().getOrdersByDateRangeStream(start, end),
      builder: (context, snapshotDeposits) {
        return StreamBuilder<List<Order>>(
          stream: DatabaseService().getOrdersByBalanceDateStream(start, end),
          builder: (context, snapshotBalances) {
            String value = '...';
            String subtext = 'Click menu to filter';

            if (snapshotDeposits.hasData && snapshotBalances.hasData) {
              final depositOrders = snapshotDeposits.data!;
              final balanceOrders = snapshotBalances.data!;
              double totalDeposits = depositOrders.fold(0, (sum, o) => sum + o.deposit);
              double totalBalances = balanceOrders.fold(0, (sum, o) => sum + o.balancePayment);
              double totalCash = totalDeposits + totalBalances;
              value = '\$${totalCash.toStringAsFixed(0)}';
            }

            return Stack(
              children: [
                StatCard(
                  title: isBento ? 'Total Revenue' : 'Cash Revenue ($label)',
                  value: value,
                  icon: Icons.paid_outlined, // 更有質感的 Icon
                  trend: subtext,
                  trendUp: true,
                  // Bento 樣式：深色背景 + 白字
                  backgroundColor: isBento ? const Color(0xFF1E1E2C) : null,
                  textColor: isBento ? Colors.white : null,
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: PopupMenuButton<String>(
                    icon: Icon(
                      Icons.filter_list, 
                      color: isBento ? Colors.white54 : Colors.grey[600]
                    ),
                    onSelected: (String choice) {
                      if (choice == 'Custom') {
                        _selectDateRange(context);
                      } else {
                        setState(() => _revenueFilterMode = choice);
                      }
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(value: 'Week', child: Text('This Week')),
                      const PopupMenuItem<String>(value: 'Month', child: Text('This Month')),
                      const PopupMenuItem<String>(value: 'Year', child: Text('This Year')),
                      const PopupMenuDivider(),
                      const PopupMenuItem<String>(value: 'Custom', child: Text('Custom Range...')),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // === 2. 項目數量分析卡片 (Bento: 高亮色塊) ===
  Widget _buildTopServiceCard({bool isBento = false}) {
    final range = _getDateRange();

    return StreamBuilder<List<Order>>(
      stream: DatabaseService().getOrdersByDateRangeStream(range.start, range.end),
      builder: (context, snapshot) {
        String topItem = 'Calculating...';
        String countText = '';
        bool hasData = false;

        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          final orders = snapshot.data!;
          Map<String, int> counts = {};

          for (var order in orders) {
            if (order.status == 'cancelled') continue;
            for (var item in order.items) {
              // 數量分析：加總 Quantity
              counts[item.service] = (counts[item.service] ?? 0) + item.quantity;
            }
          }

          if (counts.isNotEmpty) {
            var entry = counts.entries.reduce((a, b) => a.value > b.value ? a : b);
            topItem = entry.key;
            countText = '${entry.value} units sold';
            hasData = true;
          } else {
            topItem = "No Sales";
            countText = "in this period";
          }
        } else if (snapshot.hasData && snapshot.data!.isEmpty) {
          topItem = "No Data";
          countText = "in this period";
        }

        return Stack(
          children: [
            StatCard(
              title: 'Item Sales Qty',
              value: topItem,
              icon: Icons.inventory_2_outlined,
              trend: countText,
              trendUp: hasData,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CostAnalysisPage()),
                );
              },
              // Bento 樣式：琥珀金背景
              backgroundColor: isBento ? const Color(0xFFFFB74D) : null,
              textColor: isBento ? Colors.black87 : null,
            ),
             Positioned(
              top: 4,
              right: 4,
              child: PopupMenuButton<String>(
                icon: Icon(Icons.filter_list, color: isBento ? Colors.black54 : Colors.grey[400], size: 20),
                tooltip: 'Filter Time',
                onSelected: (String choice) {
                  if (choice == 'Custom') {
                    _selectDateRange(context);
                  } else {
                    setState(() => _revenueFilterMode = choice);
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(value: 'Week', child: Text('This Week')),
                  const PopupMenuItem<String>(value: 'Month', child: Text('This Month')),
                  const PopupMenuItem<String>(value: 'Year', child: Text('This Year')),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(value: 'Custom', child: Text('Custom Range...')),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // === 3. 工單狀態卡片 (Bento: 淺藍色塊) ===
  Widget _buildWorkshopStatusCard({bool isBento = false}) {
    return StreamBuilder<List<models.WorkshopOrder>>(
      stream: DatabaseService().getWorkshopOrdersStream(isOnGoingOnly: true),
      builder: (context, snapshot) {
        String value = '0';
        String subtext = 'All clear';

        if (snapshot.hasData) {
          final tasks = snapshot.data!;
          final activeTasks = tasks.where((t) => t.status != WorkshopStatus.completed).length;
          final urgentTasks = tasks.where((t) => t.status != WorkshopStatus.completed && t.priority == 'urgent').length;

          value = activeTasks.toString();
          subtext = urgentTasks > 0 ? '$urgentTasks urgent tasks!' : 'In production';
        }

        return StatCard(
          title: 'Active Jobs',
          value: value,
          icon: Icons.cut,
          trend: subtext,
          trendUp: false,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const WorkshopPage(initialScrollIndex: 0)),
            );
          },
          // Bento 樣式：淺藍背景，深青文字
          backgroundColor: isBento ? const Color(0xFFE0F7FA) : null,
          textColor: isBento ? Colors.teal[800] : null,
        );
      },
    );
  }

  // === 4. 尚欠款項卡片 (Bento: 淺紅背景) ===
  Widget _buildOutstandingBalanceCard({bool isBento = false}) {
    return StreamBuilder<List<Order>>(
      stream: DatabaseService().getOrdersStream(isIncompleteOnly: true),
      builder: (context, snapshot) {
        String value = '\$0';
        String subtext = 'All paid';
        bool hasDebt = false;

        if (snapshot.hasData) {
          final orders = snapshot.data!;
          final unpaidOrders = orders.where((o) => o.balance > 0).toList();
          double totalDebt = unpaidOrders.fold(0, (sum, o) => sum + o.balance);

          value = '\$${totalDebt.toStringAsFixed(0)}';
          if (unpaidOrders.isNotEmpty) {
            subtext = '${unpaidOrders.length} unpaid orders';
            hasDebt = true;
          }
        }

        return StatCard(
          title: 'Outstanding',
          value: value,
          icon: Icons.money_off_csred_outlined,
          trend: subtext,
          trendUp: !hasDebt,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const OrdersPage(showOutstandingOnly: true)),
            );
          },
          // Bento 樣式：淺紅背景，深紅文字
          backgroundColor: isBento ? const Color(0xFFFFEBEE) : null,
          textColor: isBento ? Colors.red[900] : null,
        );
      },
    );
  }

  // === 5. 客戶成長卡片 (Bento: 白色/預設) ===
  Widget _buildCustomerGrowthCard({bool isBento = false}) {
    return StreamBuilder<List<Customer>>(
      stream: DatabaseService().getCustomersStream(),
      builder: (context, snapshot) {
        String value = '0';
        if (snapshot.hasData) {
          value = snapshot.data!.length.toString();
        }
        return StatCard(
          title: 'Total Customers',
          value: value,
          icon: Icons.people_outline,
          trend: 'Lifetime clients',
          trendUp: true,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CustomersScreen()),
            );
          },
          // Bento 樣式：維持白色，作為視覺緩衝
          backgroundColor: isBento ? Colors.white : null,
          textColor: isBento ? Colors.black87 : null,
        );
      },
    );
  }

  // === 列表與按鈕區塊 ===
  Widget _buildRecentOrdersList(BuildContext context, List<Order> orders) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Orders',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () => Navigator.pushReplacementNamed(context, '/orders'),
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (orders.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('No orders yet')),
              )
            else
              ...orders.map((order) => _buildOrderItem(order)),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItem(Order order) {
    Color statusColor = Colors.grey;
    Color statusBg = Colors.grey[100]!;

    switch (order.status) {
      case 'completed':
        statusColor = Colors.green;
        statusBg = Colors.green[50]!;
        break;
      case 'confirmed':
        statusColor = Colors.blue;
        statusBg = Colors.blue[50]!;
        break;
      case 'pending':
        statusColor = Colors.orange;
        statusBg = Colors.orange[50]!;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.shopping_bag_outlined, color: Colors.blue),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.customerName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  order.items.isNotEmpty ? order.items.first.service : 'Order',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${order.total.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  order.status.toUpperCase(),
                  style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quick Actions',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildActionButton(
              context,
              'New Order',
              Icons.add_shopping_cart,
              Colors.blue,
              () => Navigator.pushReplacementNamed(context, '/pos'),
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              context,
              'Add Customer',
              Icons.person_add,
              Colors.green,
              () => Navigator.pushReplacementNamed(context, '/customers'),
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              context,
              'Check Workshop',
              Icons.cut,
              Colors.orange,
              () => Navigator.pushReplacementNamed(context, '/workshop'),
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              context,
              'Cost Analysis',
              Icons.analytics_outlined,
              Colors.purple,
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CostAnalysisPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.1),
          foregroundColor: color,
          elevation: 0,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        ),
      ),
    );
  }
}