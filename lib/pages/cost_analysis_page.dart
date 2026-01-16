import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/order.dart';
import '../services/database_service.dart';
import '../components/stat_card.dart';

class CostAnalysisPage extends StatefulWidget {
  const CostAnalysisPage({super.key});

  @override
  State<CostAnalysisPage> createState() => _CostAnalysisPageState();
}

class _CostAnalysisPageState extends State<CostAnalysisPage> {
  final DatabaseService _dbService = DatabaseService();
  String _timeFilter = 'Month'; // Default filter

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cost & Profit Analysis'),
        elevation: 0,
        actions: [
          // 時間篩選器
          PopupMenuButton<String>(
            icon: const Icon(Icons.calendar_today),
            onSelected: (val) => setState(() => _timeFilter = val),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'Week', child: Text('This Week')),
              const PopupMenuItem(value: 'Month', child: Text('This Month')),
              const PopupMenuItem(value: 'Year', child: Text('This Year')),
              const PopupMenuItem(value: 'All', child: Text('All Time')),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<Order>>(
        stream: _dbService.getOrdersStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // 1. 篩選訂單
          final allOrders = snapshot.data!;
          final filteredOrders = _filterOrdersByDate(allOrders);

          // 2. 計算總數據 (using actual database fields)
          double totalRevenue = 0;
          double totalCost = 0;

          for (var order in filteredOrders) {
            // 只計算有效訂單 (排除取消的)
            if (order.status != 'cancelled') {
              totalRevenue += order.total;
              totalCost += order.totalCost;
            }
          }

          double totalProfit = totalRevenue - totalCost;
          double margin = totalRevenue > 0
              ? (totalProfit / totalRevenue) * 100
              : 0;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 標題與篩選狀態
                Text(
                  'Report: $_timeFilter',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // 3. 統計卡片區 (Summary Cards)
                LayoutBuilder(
                  builder: (context, constraints) {
                    int cols = constraints.maxWidth > 800 ? 4 : 2;
                    return GridView.count(
                      crossAxisCount: cols,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.5,
                      children: [
                        StatCard(
                          title: 'Total Revenue',
                          value: '\$${totalRevenue.toStringAsFixed(0)}',
                          icon: Icons.attach_money,
                          trend: 'Gross Sales',
                        ),
                        StatCard(
                          title: 'Total Cost',
                          value: '\$${totalCost.toStringAsFixed(0)}',
                          icon: Icons.money_off,
                          trend: 'Actual Cost',
                        ),
                        StatCard(
                          title: 'Net Profit',
                          value: '\$${totalProfit.toStringAsFixed(0)}',
                          icon: Icons.account_balance_wallet,
                          trend: 'Earnings',
                        ),
                        StatCard(
                          title: 'Margin',
                          value: '${margin.toStringAsFixed(1)}%',
                          icon: Icons.pie_chart,
                          trend: 'Profitability',
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 32),
                const Text(
                  'Order Breakdown',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // 4. 詳細列表 (Detail Table)
                Card(
                  elevation: 2,
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredOrders.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final order = filteredOrders[index];
                      final isProfitable = order.totalProfit > 0;

                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isProfitable
                                ? Colors.green[50]
                                : Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isProfitable
                                ? Icons.trending_up
                                : Icons.trending_down,
                            color: isProfitable ? Colors.green : Colors.red,
                          ),
                        ),
                        title: Text(
                          '${order.customerName} (#${order.id.substring(0, 4)})',
                        ),
                        subtitle: Text(
                          DateFormat(
                            'yyyy-MM-dd',
                          ).format(order.createdAt ?? DateTime.now()),
                        ),
                        trailing: SizedBox(
                          width: 150,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Rev: \$${order.total.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Cost: \$${order.totalCost.toStringAsFixed(0)} | P: \$${order.totalProfit.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        onTap: () {
                          _showCostDetailDialog(context, order);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // 輔助方法：根據篩選器過濾訂單
  List<Order> _filterOrdersByDate(List<Order> orders) {
    final now = DateTime.now();
    return orders.where((order) {
      if (order.createdAt == null) return false;
      final date = order.createdAt!;

      switch (_timeFilter) {
        case 'Week':
          return now.difference(date).inDays <= 7;
        case 'Month':
          return date.month == now.month && date.year == now.year;
        case 'Year':
          return date.year == now.year;
        case 'All':
        default:
          return true;
      }
    }).toList();
  }

  // 輔助方法：顯示單張訂單的成本詳情
  void _showCostDetailDialog(
    BuildContext context,
    Order order,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cost Breakdown: ${order.customerName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Total Revenue'),
              trailing: Text(
                '\$${order.total.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
            const Divider(),
            ListTile(
              title: const Text('Total Cost'),
              subtitle: const Text('(Recorded Cost)'),
              trailing: Text(
                '-\$${order.totalCost.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ),
            const Divider(),
            ListTile(
              title: const Text('Net Profit'),
              trailing: Text(
                '\$${order.totalProfit.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
