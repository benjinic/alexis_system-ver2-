import 'package:flutter/material.dart';
import '../components/icon_text.dart';
import 'package:intl/intl.dart';
import '../components/stat_card.dart';
import '../components/revenue_chart.dart';
import '../services/database_service.dart';
import '../services/cost_calculation_service.dart';
import '../models/order.dart';
import '../models/customer.dart';
import '../models/service_item.dart';
import '../models/workshop_order.dart' as models;
import '../models/workshop_status.dart';
import '../l10n/app_localizations.dart';
import 'orders_page.dart';
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
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).dashboardTitle),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              AppLocalizations.of(context).overview,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).shopDescription,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
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

                    return StreamBuilder<List<ServiceItem>>(
                      stream: DatabaseService().getServicesStream(),
                      builder: (context, serviceSnapshot) {
                        final serviceByName = {
                          for (final service
                              in serviceSnapshot.data ?? <ServiceItem>[])
                            service.name: service,
                        };

                        if (constraints.maxWidth > 900) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: _buildRecentOrdersList(
                                  context,
                                  recentOrders,
                                  serviceByName,
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                flex: 1,
                                child: _buildQuickActions(context),
                              ),
                            ],
                          );
                        } else {
                          return Column(
                            children: [
                              _buildRecentOrdersList(
                                context,
                                recentOrders,
                                serviceByName,
                              ),
                              const SizedBox(height: 24),
                              _buildQuickActions(context),
                            ],
                          );
                        }
                      },
                    );
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
          Expanded(flex: 4, child: _buildDynamicRevenueCard(isBento: true)),
          const SizedBox(width: 24),

          // 中欄：營運重點 (30%)
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Expanded(
                  child: _buildTopServiceCard(isBento: true),
                ), // 人氣商品 (高亮)
                const SizedBox(height: 24),
                Expanded(
                  child: _buildWorkshopStatusCard(isBento: true),
                ), // 工廠狀態
              ],
            ),
          ),
          const SizedBox(width: 24),

          // 右欄：財務與客戶 (30%)
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Expanded(
                  child: _buildOutstandingBalanceCard(isBento: true),
                ), // 欠款
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
      label =
          '${DateFormat('MM/dd').format(start)} - ${DateFormat('MM/dd').format(end)}';
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
            String subtext = AppLocalizations.of(context).filterSubtext;

            if (snapshotDeposits.hasData && snapshotBalances.hasData) {
              final depositOrders = snapshotDeposits.data!;
              final balanceOrders = snapshotBalances.data!;
              double totalDeposits = depositOrders.fold(
                0,
                (sum, o) => sum + o.deposit,
              );
              double totalBalances = balanceOrders.fold(
                0,
                (sum, o) => sum + o.balancePayment,
              );
              double totalCash = totalDeposits + totalBalances;
              value = '\$${totalCash.toStringAsFixed(0)}';
            }

            return Stack(
              children: [
                StatCard(
                  title: isBento
                      ? AppLocalizations.of(context).totalRevenue
                      : 'Cash Revenue ($label)',
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
                    icon: IconText(
                      Icons.filter_list,
                      color: isBento ? Colors.white54 : Colors.grey[600],
                    ),
                    onSelected: (String choice) {
                      if (choice == 'Custom') {
                        _selectDateRange(context);
                      } else {
                        setState(() => _revenueFilterMode = choice);
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                            value: 'Week',
                            child: Text(
                              AppLocalizations.of(context).filterWeek,
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'Month',
                            child: Text(
                              AppLocalizations.of(context).filterMonth,
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'Year',
                            child: Text(
                              AppLocalizations.of(context).filterYear,
                            ),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem<String>(
                            value: 'Custom',
                            child: Text(
                              AppLocalizations.of(context).filterCustomRange,
                            ),
                          ),
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
      stream: DatabaseService().getOrdersByDateRangeStream(
        range.start,
        range.end,
      ),
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
              counts[item.service] =
                  (counts[item.service] ?? 0) + item.quantity;
            }
          }

          if (counts.isNotEmpty) {
            var entry = counts.entries.reduce(
              (a, b) => a.value > b.value ? a : b,
            );
            topItem = entry.key;
            countText =
                '${entry.value} ${AppLocalizations.of(context).unitsSold}';
            hasData = true;
          } else {
            topItem = AppLocalizations.of(context).noSales;
            countText = AppLocalizations.of(context).noPeriod;
          }
        } else if (snapshot.hasData && snapshot.data!.isEmpty) {
          topItem = AppLocalizations.of(context).noSales;
          countText = AppLocalizations.of(context).noPeriod;
        }

        return Stack(
          children: [
            StatCard(
              title: AppLocalizations.of(context).itemSalesQty,
              value: topItem,
              icon: Icons.inventory_2_outlined,
              trend: countText,
              trendUp: hasData,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CostAnalysisPage(),
                  ),
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
                icon: IconText(
                  Icons.filter_list,
                  color: isBento ? Colors.black54 : Colors.grey[400],
                  size: 20,
                ),
                tooltip: 'Filter Time',
                onSelected: (String choice) {
                  if (choice == 'Custom') {
                    _selectDateRange(context);
                  } else {
                    setState(() => _revenueFilterMode = choice);
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'Week',
                    child: Text(AppLocalizations.of(context).filterWeek),
                  ),
                  PopupMenuItem<String>(
                    value: 'Month',
                    child: Text(AppLocalizations.of(context).filterMonth),
                  ),
                  PopupMenuItem<String>(
                    value: 'Year',
                    child: Text(AppLocalizations.of(context).filterYear),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: 'Custom',
                    child: Text(AppLocalizations.of(context).filterCustomRange),
                  ),
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
        String subtext = AppLocalizations.of(context).allClear;

        if (snapshot.hasData) {
          final tasks = snapshot.data!;
          final activeTasks = tasks
              .where((t) => t.status != WorkshopStatus.completed)
              .length;
          final urgentTasks = tasks
              .where(
                (t) =>
                    t.status != WorkshopStatus.completed &&
                    t.priority == 'urgent',
              )
              .length;

          value = activeTasks.toString();
          subtext = urgentTasks > 0
              ? '$urgentTasks ${AppLocalizations.of(context).urgentTasks}'
              : AppLocalizations.of(context).inProduction;
        }

        return StatCard(
          title: AppLocalizations.of(context).activeJobs,
          value: value,
          icon: Icons.cut,
          trend: subtext,
          trendUp: false,
          onTap: () {
            Navigator.pushReplacementNamed(context, '/workshop');
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
        String subtext = AppLocalizations.of(context).allPaid;
        bool hasDebt = false;

        if (snapshot.hasData) {
          final orders = snapshot.data!;
          final unpaidOrders = orders.where((o) => o.balance > 0).toList();
          double totalDebt = unpaidOrders.fold(0, (sum, o) => sum + o.balance);

          value = '\$${totalDebt.toStringAsFixed(0)}';
          if (unpaidOrders.isNotEmpty) {
            subtext =
                '${unpaidOrders.length} ${AppLocalizations.of(context).unpaidOrders}';
            hasDebt = true;
          }
        }

        return StatCard(
          title: AppLocalizations.of(context).outstanding,
          value: value,
          icon: Icons.money_off_csred_outlined,
          trend: subtext,
          trendUp: !hasDebt,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    const OrdersPage(showOutstandingOnly: true),
              ),
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
          title: AppLocalizations.of(context).totalCustomers,
          value: value,
          icon: Icons.people_outline,
          trend: AppLocalizations.of(context).lifetimeClients,
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
  Widget _buildRecentOrdersList(
    BuildContext context,
    List<Order> orders,
    Map<String, ServiceItem> serviceByName,
  ) {
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
                Text(
                  AppLocalizations.of(context).recentOrders,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, '/orders'),
                  child: Text(AppLocalizations.of(context).viewAll),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (orders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(AppLocalizations.of(context).noOrdersYet),
                ),
              )
            else
              ...orders.map((order) => _buildOrderItem(order, serviceByName)),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItem(Order order, Map<String, ServiceItem> serviceByName) {
    final syncedOrder = order.items.isNotEmpty
        ? CostCalculationService.syncOrderWithServicePrices(
            order,
            serviceByName: serviceByName,
          )
        : order;
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
            child: const IconText(
              Icons.shopping_bag_outlined,
              color: Colors.blue,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.customerName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  order.items.isNotEmpty ? order.items.first.service : 'Order',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${syncedOrder.total.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
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
                  style: TextStyle(
                    fontSize: 10,
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
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
              AppLocalizations.of(context).newOrder,
              Icons.add_shopping_cart,
              Colors.blue,
              () => Navigator.pushReplacementNamed(context, '/pos'),
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              context,
              AppLocalizations.of(context).addCustomerAction,
              Icons.person_add,
              Colors.green,
              () => Navigator.pushReplacementNamed(context, '/customers'),
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              context,
              AppLocalizations.of(context).checkWorkshop,
              Icons.cut,
              Colors.orange,
              () => Navigator.pushReplacementNamed(context, '/workshop'),
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              context,
              AppLocalizations.of(context).costAnalysis,
              Icons.analytics_outlined,
              Colors.purple,
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CostAnalysisPage(),
                  ),
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
        icon: IconText(icon, size: 20),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.1),
          foregroundColor: color,
          elevation: 0,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        ),
      ),
    );
  }
}
