import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../components/icon_text.dart';
import 'package:universal_html/html.dart' as html;
import '../services/database_service.dart';
import '../services/export_service.dart';
import '../models/customer.dart';
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
  String _tierFilter = 'all';
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
          indicatorColor: Theme.of(context).colorScheme.primary,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
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
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: IconText(
                Icons.person_add,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
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

    final l10n = AppLocalizations.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Text(l10n.exportPreparing),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      await _exportDataLogic();

      if (mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.exportSuccess),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.exportFailedMsg(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() => _isExporting = false);
    }
  }

  // === 2. 標準列表 (含搜尋 + 分層篩選) ===
  Widget _buildStandardList() {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final tiers = [
      ('all', l10n.filterAll),
      ('new', l10n.tierNew),
      ('regular', l10n.tierRegular),
      ('vip', l10n.tierVip),
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (value) =>
                setState(() => _searchQuery = value.toLowerCase()),
            decoration: InputDecoration(
              hintText: l10n.searchCustomersHint,
              prefixIcon: const IconText(Icons.search),
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ),
        // Tier filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: tiers.map((t) {
              final selected = _tierFilter == t.$1;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(t.$2),
                  selected: selected,
                  onSelected: (_) => setState(() => _tierFilter = t.$1),
                  selectedColor: cs.primaryContainer,
                  checkmarkColor: cs.onPrimaryContainer,
                  labelStyle: TextStyle(
                    color: selected ? cs.onPrimaryContainer : cs.onSurface,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Customer>>(
            stream: _databaseService.getCustomersStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('${l10n.errorPrefix} ${snapshot.error}'));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allCustomers = snapshot.data ?? [];
              final customers = allCustomers.where((c) {
                final matchesSearch = _searchQuery.isEmpty ||
                    c.name.toLowerCase().contains(_searchQuery) ||
                    c.phone.contains(_searchQuery) ||
                    c.email.toLowerCase().contains(_searchQuery);
                final matchesTier = _tierFilter == 'all' || c.tier == _tierFilter;
                return matchesSearch && matchesTier;
              }).toList();

              if (customers.isEmpty) {
                return Center(child: Text(l10n.noCustomersFound));
              }

              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: customers.length,
                separatorBuilder: (_, i) =>
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

  // === 1. Top 10 列表 (總消費排行) ===
  Widget _buildTopTenList() {
    const medals = ['🥇', '🥈', '🥉'];

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          color: Theme.of(
            context,
          ).colorScheme.secondaryContainer.withValues(alpha: 0.4),
          width: double.infinity,
          child: Row(
            children: [
              IconText(
                Icons.info_outline,
                size: 16,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context).spendingInfo,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Customer>>(
            stream: _databaseService.getCustomersStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    '${AppLocalizations.of(context).errorPrefix} ${snapshot.error}',
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final sorted = [...(snapshot.data ?? [])]
                ..sort((a, b) => b.totalSpent.compareTo(a.totalSpent));
              final top10 =
                  sorted.where((c) => c.totalSpent > 0).take(10).toList();

              if (top10.isEmpty) {
                return Center(
                  child: Text(AppLocalizations.of(context).noCustomerData),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: top10.length,
                separatorBuilder: (_, i) => const Divider(),
                itemBuilder: (context, index) {
                  final customer = top10[index];
                  final label =
                      index < 3 ? medals[index] : '#${index + 1}';

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: index < 3
                          ? Colors.amber[100 * (3 - index)]
                          : Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                      foregroundColor:
                          Theme.of(context).colorScheme.onSurface,
                      child: Text(label),
                    ),
                    title: Text(
                      customer.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${AppLocalizations.of(context).totalSpent}: \$${customer.totalSpent.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.tertiary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color:
                            Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${customer.orders} ${AppLocalizations.of(context).ordersLabel}',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
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
          ),
        ),
      ],
    );
  }

  // === 輔助方法：新增客戶對話框 ===
  void _showAddCustomerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _AddCustomerDialog(
        databaseService: _databaseService,
      ),
    );
  }
}

class _AddCustomerDialog extends StatefulWidget {
  const _AddCustomerDialog({required this.databaseService});
  final DatabaseService databaseService;

  @override
  State<_AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<_AddCustomerDialog> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.addNewCustomer),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.nameLabel,
                prefixIcon: const IconText(Icons.person),
              ),
              inputFormatters: [
                TextInputFormatter.withFunction(
                  (oldValue, newValue) =>
                      newValue.copyWith(text: newValue.text.toUpperCase()),
                ),
              ],
              validator: (v) => v!.isEmpty ? l10n.requiredField : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              decoration: InputDecoration(
                labelText: l10n.phoneLabel,
                prefixIcon: const IconText(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              decoration: InputDecoration(
                labelText: l10n.emailLabel,
                prefixIcon: const IconText(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelButton),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(l10n.addButton),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final inputName = _nameController.text.trim().toUpperCase();
    final inputPhone = _phoneController.text.trim();

    final existing = await widget.databaseService.getCustomersStream().first;
    if (!mounted) return;

    final cs = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);

    final nameDup = existing.any((c) => c.name.trim().toUpperCase() == inputName);
    if (nameDup) {
      messenger.showSnackBar(SnackBar(
        content: Text('客戶名稱「$inputName」已存在'),
        backgroundColor: cs.error,
      ));
      return;
    }

    if (inputPhone.isNotEmpty) {
      final phoneDup = existing.any((c) => c.phone.trim() == inputPhone);
      if (phoneDup) {
        messenger.showSnackBar(SnackBar(
          content: Text('電話號碼「$inputPhone」已有其他客戶登記'),
          backgroundColor: cs.error,
        ));
        return;
      }
    }

    final l10n = AppLocalizations.of(context);
    try {
      await widget.databaseService.addCustomer(Customer(
        id: '',
        name: inputName,
        email: _emailController.text.trim(),
        phone: inputPhone,
        orders: 0,
        totalSpent: 0,
      ));
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(l10n.customerAddedSuccess)));
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('${l10n.errorPrefix} $e'),
        ));
      }
    }
  }
}

// === 列表項目元件 ===
bool _isFollowUpDue(DateTime? followUp) {
  if (followUp == null) return false;
  final today = DateTime.now();
  return followUp.isBefore(DateTime(today.year, today.month, today.day + 1));
}

class _CustomerListTile extends StatelessWidget {
  final Customer customer;
  final VoidCallback onTap;

  const _CustomerListTile({required this.customer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      onTap: onTap,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (_isFollowUpDue(customer.nextFollowUp))
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        customer.name,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      subtitle: (customer.phone.isEmpty && customer.totalSpent == 0)
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (customer.phone.isNotEmpty)
                  Row(
                    children: [
                      IconText(
                        Icons.phone,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        customer.phone,
                        style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                if (customer.totalSpent > 0)
                  Text(
                    '${AppLocalizations.of(context).totalSpent}: \$${customer.totalSpent.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.tertiary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TierBadge(tier: customer.tier),
          const SizedBox(width: 4),
          IconText(
            Icons.chevron_right,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _TierBadge extends StatelessWidget {
  final String tier;
  const _TierBadge({required this.tier});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    final (label, bg, fg) = switch (tier) {
      'vip' => (l10n.tierVip, cs.primaryContainer, cs.onPrimaryContainer),
      'regular' => (l10n.tierRegular, cs.secondaryContainer, cs.onSecondaryContainer),
      _ => (l10n.tierNew, cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }
}
