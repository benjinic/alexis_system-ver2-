import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../components/icon_text.dart';
import 'package:universal_html/html.dart' as html;
import '../services/database_service.dart';
import '../services/export_service.dart';
import '../models/customer.dart';
import '../models/order.dart';
import '../pages/customer_details_page.dart';
import '../l10n/app_localizations.dart';

class CustomersScreen extends StatefulWidget {
  // 移除 showTopTen 參數，改為由 Tab 控制
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final DatabaseService _databaseService = DatabaseService();
  String _searchQuery = '';
  bool _isExporting = false;

  // Tab 控制器
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // 初始化 TabController，共有 2 個分頁
    _tabController = TabController(length: 2, vsync: this);

    // 監聽 Tab 切換以更新 UI (例如 FAB 的顯示)
    _tabController.addListener(() {
      setState(() {});
    });

    _databaseService.seedMeasurementFields();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.customersTitle),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: TextButton.icon(
              onPressed: _isExporting ? null : () => _handleExport(context),
              icon: IconText(
                Icons.table_view_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              label: Text(
                l10n.exportButton,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
              style: TextButton.styleFrom(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
        // 加入 TabBar
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Theme.of(context).primaryColor,
          labelColor: Theme.of(context).primaryColor,
          unselectedLabelColor: Colors.grey,
          tabs: [
            Tab(
              icon: const IconText(Icons.star),
              text: l10n.topVips,
            ), // 分頁 1 (預設)
            Tab(
              icon: const IconText(Icons.people),
              text: l10n.allCustomers,
            ), // 分頁 2
          ],
        ),
      ),
      // 只有在 "All Customers" 分頁 (index 1) 才顯示新增按鈕
      floatingActionButton: _tabController.index == 1
          ? FloatingActionButton(
              onPressed: () => _showAddCustomerDialog(context),
              backgroundColor: Theme.of(context).primaryColor,
              child: const IconText(Icons.person_add, color: Colors.white),
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTopTenList(), // 對應分頁 1
          _buildStandardList(), // 對應分頁 2
        ],
      ),
    );
  }

  // === 匯出客戶資料 ===
  Future<void> _exportDataLogic() async {
    final customers = await _databaseService.getCustomersStream().first;
    final csvData = ExportService.generateCustomersCSV(customers);

    if (kIsWeb) {
      final bytes = utf8.encode('\uFEFF$csvData');
      final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', 'Alexis_Customers.csv')
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      await ExportService().exportCustomersToCsv(customers);
    }
  }

  Future<void> _handleExport(BuildContext context) async {
    setState(() => _isExporting = true);

    final messenger = ScaffoldMessenger.of(context);

    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Text('Preparing data for export...'),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      await _exportDataLogic();

      if (mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: const Text('✅ Export Successful!'),
            backgroundColor: Colors.green[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text('❌ Export failed: $e'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() => _isExporting = false);
    }
  }

  // === 2. 標準列表 (含搜尋功能) ===
  Widget _buildStandardList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.black),
            onChanged: (value) =>
                setState(() => _searchQuery = value.toLowerCase()),
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context).searchCustomersHint,
              hintStyle: TextStyle(color: Colors.grey[600]),
              prefixIcon: const IconText(Icons.search),
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Customer>>(
            stream: _databaseService.getCustomersStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allCustomers = snapshot.data ?? [];
              final customers = allCustomers.where((c) {
                if (_searchQuery.isEmpty) {
                  return true;
                }
                return c.name.toLowerCase().contains(_searchQuery) ||
                    c.phone.contains(_searchQuery) ||
                    c.email.toLowerCase().contains(_searchQuery);
              }).toList();

              if (customers.isEmpty) {
                return Center(
                  child: Text(AppLocalizations.of(context).noCustomersFound),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: customers.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (context, index) {
                  final customer = customers[index];
                  return _CustomerListTile(
                    customer: customer,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              CustomerDetailsPage(customer: customer),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // === 1. Top 10 列表 (近 2 年消費排行) ===
  Widget _buildTopTenList() {
    final now = DateTime.now();
    final twoYearsAgo = now.subtract(const Duration(days: 730));

    return Column(
      children: [
        // 頂部提示
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          color: Colors.amber.shade200.withValues(alpha: 0.1),
          width: double.infinity,
          child: Row(
            children: [
              const IconText(Icons.info_outline, size: 16, color: Colors.amber),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context).spendingInfo,
                style: TextStyle(color: Colors.amber[900], fontSize: 12),
              ),
            ],
          ),
        ),

        // 列表內容
        Expanded(
          child: StreamBuilder<List<Order>>(
            stream: _databaseService.getOrdersByDateRangeStream(
              twoYearsAgo,
              now,
            ),
            builder: (context, orderSnapshot) {
              if (orderSnapshot.hasError) {
                return Center(child: Text('Error: ${orderSnapshot.error}'));
              }
              if (orderSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final orders = orderSnapshot.data ?? [];
              if (orders.isEmpty) {
                return Center(
                  child: Text(AppLocalizations.of(context).noOrdersInPeriod),
                );
              }

              final Map<String, double> spendingMap = {};
              final Map<String, int> orderCountMap = {};

              for (var order in orders) {
                if (order.customerId.isNotEmpty) {
                  spendingMap[order.customerId] =
                      (spendingMap[order.customerId] ?? 0) + order.total;
                  orderCountMap[order.customerId] =
                      (orderCountMap[order.customerId] ?? 0) + 1;
                }
              }

              final sortedEntries = spendingMap.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));

              final topIds = sortedEntries.take(10).map((e) => e.key).toList();

              if (topIds.isEmpty) {
                return const Center(child: Text('No customer data found.'));
              }

              return StreamBuilder<List<Customer>>(
                stream: _databaseService.getCustomersByIds(topIds),
                builder: (context, customerSnapshot) {
                  if (customerSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final customers = customerSnapshot.data ?? [];

                  customers.sort((a, b) {
                    double spentA = spendingMap[a.id] ?? 0;
                    double spentB = spendingMap[b.id] ?? 0;
                    return spentB.compareTo(spentA);
                  });

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: customers.length,
                    separatorBuilder: (_, separatorIndex) => const Divider(),
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      final recentSpent = spendingMap[customer.id] ?? 0;
                      final recentOrders = orderCountMap[customer.id] ?? 0;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: index < 3
                              ? Colors.amber[100 * (3 - index)]
                              : Colors.grey[200],
                          foregroundColor: Colors.black87,
                          child: Text('#${index + 1}'),
                        ),
                        title: Text(
                          customer.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${AppLocalizations.of(context).twoYearSpent} \$${recentSpent.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$recentOrders ${AppLocalizations.of(context).ordersLabel}',
                            style: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  CustomerDetailsPage(customer: customer),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // === 輔助方法：新增客戶對話框 ===
  void _showAddCustomerDialog(BuildContext context) {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).addNewCustomer),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: IconText(Icons.person),
                ),
                inputFormatters: [
                  TextInputFormatter.withFunction(
                    (oldValue, newValue) =>
                        newValue.copyWith(text: newValue.text.toUpperCase()),
                  ),
                ],
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: IconText(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: IconText(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context).cancelButton),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                try {
                  final newCustomer = Customer(
                    id: '',
                    name: nameController.text.trim(),
                    email: emailController.text.trim(),
                    phone: phoneController.text.trim(),
                    orders: 0,
                    totalSpent: 0,
                  );

                  await _databaseService.addCustomer(newCustomer);

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppLocalizations.of(context).customerAddedSuccess,
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            child: Text(AppLocalizations.of(context).addButton),
          ),
        ],
      ),
    );
  }
}

// === 列表項目元件 ===
class _CustomerListTile extends StatelessWidget {
  final Customer customer;
  final VoidCallback onTap;

  const _CustomerListTile({required this.customer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        child: Text(
          customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
          style: TextStyle(
            color: Theme.of(context).primaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        customer.name,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      subtitle: customer.phone.isNotEmpty
          ? Row(
              children: [
                IconText(Icons.phone, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(customer.phone, style: TextStyle(color: Colors.grey[600])),
              ],
            )
          : null,
      trailing: const IconText(Icons.chevron_right, color: Colors.grey),
    );
  }
}
