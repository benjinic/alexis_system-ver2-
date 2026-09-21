import 'dart:async';
import 'package:flutter/material.dart';
import '../components/icon_text.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/order.dart';
import '../models/workshop_order.dart';
import '../models/workshop_status.dart';
import '../models/customer.dart';
import '../models/material_item.dart';
import '../models/service_item.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../services/cost_calculation_service.dart';
import '../services/pdf_service.dart';
import '../services/bespoke_import_service.dart';
import '../services/bespoke_cart_mapper.dart';
import '../providers/cart_provider.dart';
import '../components/order_item_dialog.dart';

class POSPage extends StatefulWidget {
  final Order? orderForEdit;

  // === 訂製訂單匯入用（可選，唔影響原有 POS 落單流程） ===
  final String? prefillCustomerName;
  final DateTime? prefillDeliveryDate;
  final String? prefillNotes;
  final void Function(String orderId)? onOrderSaved;

  const POSPage({
    super.key,
    this.orderForEdit,
    this.prefillCustomerName,
    this.prefillDeliveryDate,
    this.prefillNotes,
    this.onOrderSaved,
  });

  @override
  State<POSPage> createState() => _POSPageState();
}

class _POSPageState extends State<POSPage> {
  final DatabaseService _dbService = DatabaseService();

  // Service outsourcing baseline table (minimum per-item outsourcing cost).
  static const Map<String, double> _outsourcingCostBaselines = {
    'Suit': 1400,
    'Shirt': 400,
    'Pants': 500,
  };

  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _depositController = TextEditingController();
  List<BalancePayment> _payments = [];
  final TextEditingController _fixedCostController = TextEditingController();
  final TextEditingController _laborCostController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  DateTime? _deliveryDate;

  String? _selectedCustomerId;
  Customer? _selectedCustomer;
  String? _importedBespokeId; // 由 Bespoke 匯入時，儲存成功後要回寫嘅訂製訂單 ID

  bool _isLoading = false;
  String _selectedPaymentMethod = 'Cash';

  final List<String> _paymentMethods = [
    'Cash',
    'Visa',
    'Master',
    'AE',
    'Cup',
    'Other',
  ];

  late Stream<DateTime> _timeStream;
  late Stream<List<Customer>> _customersStream;
  Stream<int>? _nextOrderIdStream;
  Map<String, ServiceItem> _serviceByName = {};
  String _currencySymbol = 'HK\$';

  // 已完成/取消的訂單保留原始財務數值；confirmed 訂單仍可編輯並重算合計。
  bool get _isHistorical {
    if (widget.orderForEdit == null) return false;
    final status = widget.orderForEdit!.status.toLowerCase();
    return status == 'completed' || status == 'cancelled';
  }

  static String _codeToSymbol(String code) => switch (code) {
    'USD' => 'US\$',
    'HKD' => 'HK\$',
    'TWD' => 'NT\$',
    'EUR' => '€',
    'GBP' => '£',
    _ => code,
  };

  @override
  void initState() {
    super.initState();
    SettingsService().loadSettings().then((s) {
      final sym = _codeToSymbol(s['currency'] as String? ?? 'HKD');
      if (mounted) setState(() => _currencySymbol = sym);
    });
    _timeStream = Stream.periodic(
      const Duration(seconds: 1),
      (_) => DateTime.now(),
    ).asBroadcastStream();
    _customersStream = _dbService.getCustomersStream();

    unawaited(
      _dbService.ensureMinimumServiceOutsourcingCosts(
        minimumCostByService: _outsourcingCostBaselines,
      ),
    );

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cart = context.read<CartProvider>();
      cart.clearCart();

      if (widget.orderForEdit != null) {
        _loadExistingOrder(widget.orderForEdit!);
      }
    });

    if (widget.orderForEdit == null) {
      _nextOrderIdStream = _dbService.getNextOrderIdStream();
    }
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _discountController.dispose();
    _depositController.dispose();
    _fixedCostController.dispose();
    _laborCostController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _loadExistingOrder(Order order) {
    setState(() {
      context.read<CartProvider>().loadOrderItems(order.items);

      _selectedCustomerId = order.customerId.isNotEmpty
          ? order.customerId
          : null;
      _customerNameController.text = order.customerName;

      _discountController.text = order.discount == 0
          ? ''
          : order.discount.toStringAsFixed(0);
      _depositController.text = order.deposit == 0
          ? ''
          : order.deposit.toStringAsFixed(0);

      _payments = List.of(order.payments);
      _fixedCostController.text = order.fixedCost == 0
          ? ''
          : order.fixedCost.toStringAsFixed(0);
      _laborCostController.text = order.laborCost == 0
          ? ''
          : order.laborCost.toStringAsFixed(0);

      if (_paymentMethods.contains(order.paymentMethod)) {
        _selectedPaymentMethod = order.paymentMethod;
      } else {
        _selectedPaymentMethod = 'Other';
      }

      _deliveryDate = order.deliveryDate;
      _notesController.text = order.notes;
    });
  }

  // === 從 Bespoke 匯入 ===
  // 只預填客人資料、訂金、交貨日同備注；服務項目同價錢由職員自己加，
  // 儲存時單號由 allocateOrderId 分配（即 POS 最新單號）。
  Future<void> _importFromBespoke() async {
    final picked = await showDialog<BespokeOrderSummary>(
      context: context,
      builder: (_) => _BespokeOrderPickerDialog(service: BespokeImportService()),
    );
    if (picked == null || !mounted) return;

    // 盡量對應返 POS 現有客人：先比電話，再比名稱。
    Customer? match;
    try {
      final customers = await _dbService.getCustomersStream().first;
      final name = picked.clientName.trim().toLowerCase();
      // Bespoke 建單時由客人名單揀選嘅，直接用 customerId 對返同一個客人。
      if (picked.customerId.isNotEmpty) {
        match = customers.where((c) => c.id == picked.customerId).firstOrNull;
      }
      if (match == null) {
        for (final c in customers) {
          if (picked.phone.isNotEmpty && c.phone == picked.phone) {
            match = c;
            break;
          }
        }
      }
      match ??= customers
          .where((c) => c.name.trim().toLowerCase() == name)
          .firstOrNull;
    } catch (_) {
      // 讀唔到客人列表就當冇對應，之後照舊建立新客人。
    }
    if (!mounted) return;

    setState(() {
      _importedBespokeId = picked.id;
      _selectedCustomerId = match?.id;
      _selectedCustomer = match;
      _customerNameController.text = match?.name ?? picked.clientName;
      _depositController.text = picked.deposit > 0
          ? (picked.deposit == picked.deposit.roundToDouble()
                ? picked.deposit.toStringAsFixed(0)
                : '${picked.deposit}')
          : '';
      if (picked.dueDate != null) _deliveryDate = picked.dueDate;
      final existing = _notesController.text.trim();
      _notesController.text = existing.isEmpty
          ? picked.toNotesText()
          : '$existing\n${picked.toNotesText()}';
    });

    // 每件衣服各開一次 POS 原本嘅「新增項目」視窗，預填服務、布料、用量同價錢；
    // 計價同成本全部由 OrderItemDialog 處理，職員照平時咁確認或修改。
    // 按 Cancel 就略過該件（之後可喺購物車自己加）。
    var addedCount = 0;
    if (picked.items.isNotEmpty) {
      var inventory = <MaterialItem>[];
      try {
        inventory = await _dbService.getInventory();
      } catch (_) {
        // 讀唔到庫存就當冇對應，布料成本之後可喺購物車編輯。
      }
      if (!mounted) return;
      final cart = context.read<CartProvider>();
      final cartBefore = cart.items.length;
      final services = _serviceByName.values.toList();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < picked.items.length; i++) {
        if (!mounted) return;
        final raw = picked.items[i];
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => OrderItemDialog(
            existingItem: buildPrefillItem(
              id: '${stamp + i}',
              bespokeItem: raw,
              services: services,
              inventory: inventory,
            ),
            asNewItem: true,
            contextNote: describeBespokeItem(
              raw,
              index: i,
              total: picked.items.length,
              inventory: inventory,
            ),
          ),
        );
      }
      addedCount = cart.items.length - cartBefore;
    }
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          addedCount > 0
              ? '已帶入「${picked.clientName}」的訂製資料，並加入 $addedCount 項到購物車'
                    '（訂製總價 $_currencySymbol${picked.totalPrice.toStringAsFixed(0)}），請核對後建立訂單'
              : '已帶入「${picked.clientName}」的訂製資料（訂製總價 '
                    '$_currencySymbol${picked.totalPrice.toStringAsFixed(0)}），請加入服務項目後建立訂單',
        ),
      ),
    );
  }

  void _showCustomerSelectSheet(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        String searchQuery = '';
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setModalState) {
                return Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            AppLocalizations.of(context).selectCustomer,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const IconText(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        decoration: InputDecoration(
                          hintText: AppLocalizations.of(
                            context,
                          ).searchCustomerHint,
                          prefixIcon: const IconText(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                        ),
                        onChanged: (val) => setModalState(
                          () => searchQuery = val.toLowerCase(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: StreamBuilder<List<Customer>>(
                          stream: _customersStream,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return Center(
                                child: Text('Error: ${snapshot.error}'),
                              );
                            }
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            final allCustomers = snapshot.data ?? [];
                            final filteredCustomers = allCustomers.where((c) {
                              return c.name.toLowerCase().contains(
                                    searchQuery,
                                  ) ||
                                  c.phone.contains(searchQuery);
                            }).toList();

                            if (filteredCustomers.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconText(
                                      Icons.person_off,
                                      size: 48,
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No customer found for "$searchQuery"',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _showAddCustomerDialog(
                                          context,
                                          initialName: searchQuery,
                                        );
                                      },
                                      icon: const IconText(Icons.person_add),
                                      label: Text(
                                        AppLocalizations.of(
                                          context,
                                        ).addNewCustomer,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return ListView.separated(
                              itemCount: filteredCustomers.length,
                              separatorBuilder: (_, separatorIndex) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final customer = filteredCustomers[index];
                                final isSelected =
                                    customer.id == _selectedCustomerId;
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isSelected
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                                    child: Text(
                                      customer.name.isNotEmpty
                                          ? customer.name[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: isSelected
                                            ? Theme.of(context).colorScheme.onPrimary
                                            : Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    customer.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    customer.phone.isNotEmpty
                                        ? customer.phone
                                        : 'No phone',
                                  ),
                                  trailing: isSelected
                                      ? IconText(
                                          Icons.check_circle,
                                          color: Theme.of(context).colorScheme.primary,
                                        )
                                      : null,
                                  onTap: () {
                                    setState(() {
                                      _selectedCustomerId = customer.id;
                                      _selectedCustomer = customer;
                                      _customerNameController.text =
                                          customer.name;
                                    });
                                    Navigator.pop(context);
                                  },
                                );
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
          ),
        );
      },
    );
  }

  void _showAddCustomerDialog(BuildContext context, {String? initialName}) {
    final nameController = TextEditingController(text: initialName ?? '');
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).addNewCustomer),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Name *',
                    hintText: 'Customer name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                  ),
                  inputFormatters: [
                    TextInputFormatter.withFunction(
                      (oldValue, newValue) =>
                          newValue.copyWith(text: newValue.text.toUpperCase()),
                    ),
                  ],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppLocalizations.of(ctx).nameRequiredError;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  decoration: InputDecoration(
                    labelText: 'Phone',
                    hintText: 'Customer phone',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    hintText: 'customer@example.com',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(value)) {
                        return AppLocalizations.of(ctx).emailInvalidError;
                      }
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx).cancelButton),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(ctx);
                final l10n = AppLocalizations.of(context);
                try {
                  final newCustomer = Customer(
                    id: '',
                    name: nameController.text.trim(),
                    phone: phoneController.text.trim(),
                    email: emailController.text.trim(),
                    orders: 0,
                    totalSpent: 0,
                  );
                  final id = await _dbService.addCustomer(newCustomer);
                  if (!mounted) return;
                  setState(() {
                    _selectedCustomerId = id;
                    _selectedCustomer = newCustomer.copyWith(id: id);
                    _customerNameController.text = nameController.text.trim();
                  });
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(l10n.customerAddedSuccess),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  navigator.pop();
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              }
            },
            child: Text(AppLocalizations.of(ctx).addCustomerAction),
          ),
        ],
      ),
    );
  }

  void _showCustomerMeasurementsDialog(Customer customer) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const IconText(Icons.straighten, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${customer.name} — ${l10n.bodyMeasurements}',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: customer.measurements.isEmpty
            ? Text(l10n.noMeasurements)
            : Wrap(
                spacing: 12,
                runSpacing: 12,
                children: customer.measurements.entries.map((entry) {
                  return Container(
                    width: 110,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(ctx).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          entry.key,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entry.value,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.closeButton),
          ),
        ],
      ),
    );
  }

  void _openItemDialog({OrderItem? existingItem, int? index}) {
    showDialog(
      context: context,
      builder: (context) =>
          OrderItemDialog(existingItem: existingItem, index: index),
    );
  }

  Future<void> _showFabricImageDialog({
    required List<OrderItem> orderItems,
    required OrderItem selectedItem,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _FabricGalleryDialog(
        dbService: _dbService,
        orderItems: orderItems,
        selectedItem: selectedItem,
      ),
    );
  }

  // === Updated _processOrder to use Provider ===
  Future<void> _processOrder() async {
    final cart = context.read<CartProvider>();
    String finalCustomerName = _customerNameController.text.trim();

    if (cart.items.isEmpty ||
        (_selectedCustomerId == null && finalCustomerName.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).pleaseAddItemsMsg),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final allServices = await _dbService.getServicesStream().first;
      final serviceByName = {
        for (final service in allServices) service.name: service,
      };
      // 歷史鎖：已完成/取消的訂單保留原始數值，不重算
      final syncedItems = _isHistorical
          ? cart.items
          : CostCalculationService.syncItemsWithServicePrices(
              cart.items,
              serviceByName: serviceByName,
            );
      double subtotal = _isHistorical
          ? widget.orderForEdit!.subtotal
          : CostCalculationService.calculateSubtotalFromItems(
              syncedItems,
              serviceByName: serviceByName,
            );
      double materialCost = _isHistorical
          ? widget.orderForEdit!.materialCost
          : cart.totalCost;
      double laborCost = double.tryParse(_laborCostController.text) ??
          (_isHistorical ? widget.orderForEdit!.laborCost : 0.0);
      double outsourcingCost = _isHistorical
          ? widget.orderForEdit!.outsourcingCost
          : CostCalculationService.calculateOutsourcingCostFromItems(
              syncedItems,
              serviceByName: serviceByName,
            );
      double fixedCost =
          double.tryParse(_fixedCostController.text) ??
          (_isHistorical ? widget.orderForEdit!.fixedCost : 0.0);
      double totalCost = _isHistorical
          ? widget.orderForEdit!.totalCost
          : CostCalculationService.calculateTotalCost(
              materialCost: materialCost,
              outsourcingCost: outsourcingCost,
              fixedCost: fixedCost,
              laborCost: laborCost,
            );
      double discount =
          double.tryParse(_discountController.text) ??
          (_isHistorical ? widget.orderForEdit!.discount : 0.0);
      double total = _isHistorical
          ? widget.orderForEdit!.total
          : (subtotal - discount).clamp(0, double.infinity);

      double deposit = double.tryParse(_depositController.text) ?? 0.0;
      double balancePayment =
          _payments.fold(0.0, (sum, p) => sum + p.amount);
      double balance = total - (deposit + balancePayment);
      if (balance < 0) balance = 0;

      double totalProfit = _isHistorical
          ? widget.orderForEdit!.totalProfit
          : (total - totalCost);
      String orderStatus = balance <= 0 ? 'completed' : 'confirmed';

      bool isEditMode = widget.orderForEdit != null;
      String orderId = isEditMode ? widget.orderForEdit!.id : '';

      String customerId = '';
      if (_selectedCustomerId != null) {
        customerId = _selectedCustomerId!;
      } else if (!isEditMode && customerId.isEmpty) {
        final newCustomer = Customer(
          id: '',
          name: finalCustomerName,
          email: '',
          phone: '',
          orders: 0,
          totalSpent: 0,
        );
        customerId = await _dbService.addCustomer(newCustomer);
      }

      final orderData = Order(
        id: orderId,
        uniqueId: isEditMode
            ? widget.orderForEdit!.uniqueId
            : DateTime.now().millisecondsSinceEpoch.toString(),
        customerId: customerId,
        customerName: finalCustomerName,
        items: syncedItems,
        subtotal: subtotal,
        discount: discount,
        total: total,
        deposit: deposit,
        balancePayment: balancePayment,
        balancePaymentMethod:
            _payments.isNotEmpty ? _payments.last.method : null,
        balancePaidDate:
            _payments.isNotEmpty ? _payments.last.paidAt : null,
        balance: balance,
        payments: _payments,
        materialCost: materialCost,
        laborCost: laborCost,
        outsourcingCost: outsourcingCost,
        fixedCost: fixedCost,
        totalCost: totalCost,
        totalProfit: totalProfit,
        status: orderStatus,
        paymentMethod: _selectedPaymentMethod,
        createdAt: isEditMode ? widget.orderForEdit!.createdAt : DateTime.now(),
        updatedAt: DateTime.now(),
        deliveryDate: _deliveryDate,
        notes: _notesController.text.trim(),
      );

      // Order object for printing (will be updated with ID after save)
      Order orderForPrinting = orderData;
      // Collect generated workshop orders for job ticket printing
      List<WorkshopOrder> generatedTickets = [];
      final postSaveWarnings = <String>[];

      if (isEditMode) {
        await _dbService.updateOrder(orderData);
      } else {
        orderId = await _dbService.addOrder(orderData);
        orderForPrinting = orderData.copyWith(id: orderId);

        // 由 Bespoke 匯入：訂單已建立，回寫關聯。失敗只提醒，唔影響訂單本身。
        final bespokeId = _importedBespokeId;
        if (bespokeId != null) {
          try {
            await BespokeImportService().markImported(
              bespokeId,
              posOrderId: orderId,
            );
          } catch (error) {
            debugPrint('Warning: failed to mark bespoke order imported: $error');
            postSaveWarnings.add('Bespoke 訂單未能標記為已匯入：$error');
          }
        }

        for (var item in syncedItems) {
          if (item.sendToWorkshop) {
            // Look up service duration from settings
            int productionDays = 7; // Default fallback
            try {
              final serviceSettings = allServices.firstWhere(
                (s) => s.name == item.service,
              );
              productionDays = serviceSettings.durationDays;
            } catch (error) {
              // Service not found in settings, use default
              debugPrint(
                'Warning: Service settings not found for ${item.service}, using default 7 days.',
              );
            }

            // Calculate accurate due date based on service duration
            final calculatedDueDate = DateTime.now().add(
              Duration(days: productionDays),
            );

            // === 組合詳細的項目名稱 ===
            String detailedItemName = item.service.toUpperCase();

            // 如果有布料名稱，加到前面 (例如: WHITE PIMA COTTON SHIRT)
            if (item.fabricName != null && item.fabricName!.isNotEmpty) {
              detailedItemName =
                  '${item.fabricName!.toUpperCase()} $detailedItemName';
            }

            // 如果有布料代碼，加到後面 (例如: WHITE PIMA COTTON SHIRT BN0033-1)
            if (item.fabricId != null && item.fabricId!.isNotEmpty) {
              detailedItemName = '$detailedItemName ${item.fabricId}';
            }
            // === 組合結束 ===

            final ticket = WorkshopOrder(
              id: '',
              orderId: orderId, // <--- 這裡傳入訂單編號 (例如 "14039")
              customer: finalCustomerName,
              item: detailedItemName,
              status: WorkshopStatus.measuring,
              priority: 'normal',
              dueDate: calculatedDueDate,
              progress: 0,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              isFabricOrdered: false,
            );

            try {
              await _dbService.addWorkshopOrder(ticket);
              generatedTickets.add(ticket);
            } catch (error) {
              debugPrint('Warning: failed to create workshop ticket: $error');
              postSaveWarnings.add('Workshop ticket was not created.');
            }
          }
        }
      }

      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).orderProcessedSuccess),
          ),
        );
      }

      // 編輯模式：直接關閉，不彈印單對話框
      if (mounted && isEditMode) {
        Navigator.pop(context);
        return;
      }

      // === Step 4: Ask to print receipt ===
      if (mounted) {
        bool? printReceipt = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text(AppLocalizations.of(ctx).printReceiptTitle),
            content: Text(AppLocalizations.of(ctx).printReceiptQuestion),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(AppLocalizations.of(ctx).noButton),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(AppLocalizations.of(ctx).printButton),
              ),
            ],
          ),
        );

        if (printReceipt == true && mounted) {
          await PdfService().printReceipt(context, orderForPrinting);
        }
      }

      // === Step 5: Ask to print job tickets if any ===
      if (mounted && generatedTickets.isNotEmpty) {
        bool? printTickets = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text(AppLocalizations.of(ctx).printJobTicketsTitle),
            content: Text(
              AppLocalizations.of(ctx).printJobTicketsBody(generatedTickets.length),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(AppLocalizations.of(ctx).noButton),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(AppLocalizations.of(ctx).printButton),
              ),
            ],
          ),
        );

        if (printTickets == true && mounted) {
          for (var ticket in generatedTickets) {
            await PdfService().printWorkshopOrder(
              context,
              ticket.copyWith(id: orderId),
            );
          }
        }
      }

      // === Step 5.5: Fabric ordering reminder ===
      if (mounted && !isEditMode) {
        final fabricItems = syncedItems
            .where(
              (item) =>
                  (item.fabricId ?? '').trim().isNotEmpty ||
                  (item.fabricName ?? '').trim().isNotEmpty ||
                  item.fabricUsed > 0,
            )
            .toList();

        if (fabricItems.isNotEmpty) {
          final bool? markOrdered = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.local_shipping_outlined, color: Theme.of(ctx).colorScheme.tertiary),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(ctx).fabricReminderTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(ctx).fabricReminderSubtitle,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    ...fabricItems.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.texture,
                              size: 16,
                              color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (item.fabricName?.isNotEmpty == true
                                            ? item.fabricName!
                                            : item.fabricId ?? '')
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${item.service}'
                                    '${item.fabricUsed > 0 ? '  ·  ${item.fabricUsed.toStringAsFixed(1)} m' : ''}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(AppLocalizations.of(ctx).laterButton),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check, size: 16),
                  label: Text(AppLocalizations.of(ctx).markFabricOrdered),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.tertiary,
                    foregroundColor: Theme.of(ctx).colorScheme.onTertiary,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ],
            ),
          );

          if (markOrdered == true && mounted) {
            try {
              await _dbService.updateOrderFabricRequiredItemsStatus(
                orderId: orderId,
                isFabricOrdered: true,
              );
              await _dbService.updateWorkshopOrdersFabricStatus(
                orderId: orderId,
                isFabricOrdered: true,
              );
            } catch (error) {
              debugPrint('Warning: failed to mark fabric ordered: $error');
              postSaveWarnings.add('Fabric ordered status was not updated.');
            }
          }
        }
      }

      if (mounted && postSaveWarnings.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(postSaveWarnings.toSet().join(' ')),
            backgroundColor: Theme.of(context).colorScheme.tertiary,
          ),
        );
      }

      // === Step 6: Cleanup and navigation ===
      if (mounted) {
        if (isEditMode) {
          Navigator.pop(context);
        } else {
          // Clear cart via Provider
          cart.clearCart();

          setState(() {
            _customerNameController.clear();
            _discountController.clear();
            _depositController.clear();
            _payments = [];
            _fixedCostController.clear();
            _selectedCustomerId = null;
            _selectedCustomer = null;
            _laborCostController.clear();
            _selectedPaymentMethod = 'Cash';
            // 匯入嘅備注同交貨日屬於上一張單，唔好帶落下一張。
            if (_importedBespokeId != null) {
              _notesController.clear();
              _deliveryDate = null;
              _importedBespokeId = null;
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget titleWidget;
    Color? appBarColor;

    if (widget.orderForEdit != null) {
      titleWidget = Text(
        'Edit Order #${widget.orderForEdit!.id}',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      );
      appBarColor = Theme.of(context).colorScheme.secondaryContainer;
    } else {
      titleWidget = StreamBuilder<int>(
        stream: _nextOrderIdStream,
        builder: (context, snapshot) {
          String idText = snapshot.hasData ? '#${snapshot.data}' : '...';
          return Text(
            'New Order $idText',
            style: const TextStyle(fontWeight: FontWeight.bold),
          );
        },
      );
      appBarColor = null;
    }

    return Scaffold(
      appBar: AppBar(
        title: titleWidget,
        elevation: 0,
        backgroundColor: appBarColor,
        actions: [
          if (widget.orderForEdit == null)
            TextButton.icon(
              icon: const IconText(Icons.checkroom_outlined),
              label: Text(
                _importedBespokeId == null ? '從 Bespoke 匯入' : '已帶入 Bespoke 訂單',
              ),
              onPressed: _isLoading ? null : _importFromBespoke,
            ),
          const SizedBox(width: 8),
        ],
      ),
      // 修正響應式佈局：使用 LayoutBuilder
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                // 定義分界點：寬度小於 900 視為手機/窄螢幕
                final isMobile = constraints.maxWidth < 900;

                if (isMobile) {
                  // === 手機版 (Mobile) ===
                  // 垂直佈局 + 可捲動
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildCartCard(), // 購物車
                        const SizedBox(height: 16),
                        _buildSummaryCard(), // 結帳區
                      ],
                    ),
                  );
                } else {
                  // === 電腦/平板版 (Desktop/Tablet) ===
                  // 修改重點：在 Expanded 內部加入 SingleChildScrollView
                  // 這樣當視窗高度不足時，左右兩欄都可以獨立捲動，不會出現 Overflow 錯誤
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 左側購物車
                      Expanded(
                        flex: 2,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
                          // 調整 Padding 讓滾動條不貼邊
                          child: _buildCartCard(),
                        ),
                      ),
                      const SizedBox(width: 24),
                      // 右側結帳區 (容易 Overflow 的地方)
                      Expanded(
                        flex: 1,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                          // 調整 Padding
                          child: _buildSummaryCard(),
                        ),
                      ),
                    ],
                  );
                }
              },
            ),
    );
  }

  Widget _buildCartCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Consumer<CartProvider>(
          builder: (context, cart, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.of(context).cartItems,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    StreamBuilder<DateTime>(
                      stream: _timeStream,
                      builder: (context, snapshot) {
                        final time = snapshot.data ?? DateTime.now();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              DateFormat('yyyy-MM-dd').format(time),
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                            Text(
                              DateFormat('HH:mm:ss').format(time),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 16),

                if (cart.items.isEmpty)
                  Container(
                    height: 300, // 給空狀態一個固定高度
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconText(
                          Icons.shopping_cart_outlined,
                          size: 64,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          AppLocalizations.of(context).cartEmpty,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () => _openItemDialog(),
                          icon: const IconText(Icons.add),
                          label: Text(
                            AppLocalizations.of(context).addFirstItem,
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: cart.items.length,
                    separatorBuilder: (_, separatorIndex) => const Divider(),
                    itemBuilder: (context, index) {
                      final item = cart.items[index];
                      final unitPrice = _isHistorical
                          ? item.price
                          : CostCalculationService.resolveUnitPrice(
                              item,
                              serviceByName: _serviceByName,
                            );
                      final itemOutsourcingCost = _isHistorical
                          ? item.cost
                          : CostCalculationService.calculateItemOutsourcingCost(
                              item,
                              serviceByName: _serviceByName,
                            );
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: widget.orderForEdit != null
                            ? () => _showFabricImageDialog(
                                orderItems: cart.items,
                                selectedItem: item,
                              )
                            : null,
                        title: Row(
                          children: [
                            Text(
                              item.service,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (item.quantity > 1) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'x${item.quantity}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item.fabricName != null)
                              Text('${item.fabricName} (${item.fabricUsed}m)')
                            else
                              Text(AppLocalizations.of(context).noFabricText),
                            Row(
                              children: [
                                if (item.fabricName != null) ...[
                                  Text(
                                    'Mat: $_currencySymbol${item.cost.toStringAsFixed(1)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                if (itemOutsourcingCost > 0)
                                  Text(
                                    'Out: $_currencySymbol${itemOutsourcingCost.toStringAsFixed(1)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.tertiary,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.orderForEdit == null) ...[
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: IconText(
                                  item.sendToWorkshop
                                      ? Icons.engineering
                                      : Icons.engineering_outlined,
                                  color: item.sendToWorkshop
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                  size: 20,
                                ),
                                tooltip: item.sendToWorkshop
                                    ? 'Remove from workshop'
                                    : 'Send to workshop',
                                onPressed: () => cart.updateItem(
                                  index,
                                  item.copyWith(
                                    sendToWorkshop: !item.sendToWorkshop,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              '$_currencySymbol${(unitPrice * item.quantity).toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 編輯模式始終顯示修改/刪除按鈕；歷史鎖只鎖財務數值
                            if (!_isHistorical ||
                                widget.orderForEdit != null) ...[
                              IconButton(
                                icon: IconText(
                                  Icons.edit,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                tooltip: AppLocalizations.of(
                                  context,
                                ).editItemTooltip,
                                onPressed: () => _openItemDialog(
                                  existingItem: item,
                                  index: index,
                                ),
                              ),
                              IconButton(
                                icon: IconText(
                                  Icons.delete,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                onPressed: () => cart.removeItem(index),
                              ),
                            ] else ...[
                              Tooltip(
                                message: 'Historical Order (Locked)',
                                child: Icon(
                                  Icons.lock_outline,
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                  size: 20,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  if (!_isHistorical || widget.orderForEdit != null)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _openItemDialog(),
                        icon: const IconText(Icons.add),
                        label: Text(AppLocalizations.of(context).addItemButton),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPaymentsSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Balance Payments',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (!_isHistorical)
                TextButton.icon(
                  onPressed: _showAddPaymentDialog,
                  icon: const IconText(Icons.add, size: 16),
                  label: const Text('Add'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
            ],
          ),
          if (_payments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No payments recorded',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            )
          else
            ..._payments.asMap().entries.map((entry) {
              final i = entry.key;
              final p = entry.value;
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    IconText(
                      Icons.receipt_long,
                      size: 15,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('MM/dd/yy').format(p.paidAt),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        p.method,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$_currencySymbol${p.amount.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (!_isHistorical) ...[
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () => setState(() => _payments.removeAt(i)),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: IconText(
                            Icons.close,
                            size: 15,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  void _showAddPaymentDialog() {
    final amountController = TextEditingController();
    String method = _paymentMethods.first;
    DateTime paidAt = DateTime.now();

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Balance Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixIcon: IconText(Icons.payments_outlined),
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}')),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(
                  labelText: 'Payment Method',
                  border: OutlineInputBorder(),
                ),
                items: _paymentMethods
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setDialogState(() => method = v!),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: paidAt,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) {
                    setDialogState(() => paidAt = picked);
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Payment Date',
                    prefixIcon: IconText(Icons.calendar_today_outlined),
                    border: OutlineInputBorder(),
                  ),
                  child: Text(DateFormat('yyyy-MM-dd').format(paidAt)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final amount =
                    double.tryParse(amountController.text) ?? 0.0;
                if (amount <= 0) return;
                setState(() {
                  _payments.add(BalancePayment(
                    amount: amount,
                    method: method,
                    paidAt: paidAt,
                  ));
                });
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final cart = context.watch<CartProvider>();

    // 歷史鎖：已完成/取消的訂單保留原始數值，不重算
    double subtotal = _isHistorical
        ? widget.orderForEdit!.subtotal
        : CostCalculationService.calculateSubtotalFromItems(
            cart.items,
            serviceByName: _serviceByName,
          );
    double materialCost = _isHistorical
        ? widget.orderForEdit!.materialCost
        : cart.totalCost;
    double outsourcingCost = _isHistorical
        ? widget.orderForEdit!.outsourcingCost
        : CostCalculationService.calculateOutsourcingCostFromItems(
            cart.items,
            serviceByName: _serviceByName,
          );
    double fixedCost =
        double.tryParse(_fixedCostController.text) ??
        (_isHistorical ? widget.orderForEdit!.fixedCost : 0.0);
    double laborCostDisplay =
        double.tryParse(_laborCostController.text) ??
        (_isHistorical ? widget.orderForEdit!.laborCost : 0.0);
    double totalCost = _isHistorical
        ? widget.orderForEdit!.totalCost
        : CostCalculationService.calculateTotalCost(
            materialCost: materialCost,
            outsourcingCost: outsourcingCost,
            fixedCost: fixedCost,
            laborCost: laborCostDisplay,
          );
    double discount =
        double.tryParse(_discountController.text) ??
        (_isHistorical ? widget.orderForEdit!.discount : 0.0);
    double total = _isHistorical
        ? widget.orderForEdit!.total
        : (subtotal - discount).clamp(0, double.infinity);
    double totalProfit = _isHistorical
        ? widget.orderForEdit!.totalProfit
        : (total - totalCost);

    double deposit = double.tryParse(_depositController.text) ?? 0.0;
    double balancePayment =
        _payments.fold(0.0, (sum, p) => sum + p.amount);
    double balance = total - (deposit + balancePayment);

    String btnText = widget.orderForEdit != null
        ? 'UPDATE ORDER'
        : 'PROCESS ORDER';
    bool isEditMode = widget.orderForEdit != null;

    return Card(
      // margin: const EdgeInsets.fromLTRB(0, 16, 16, 16), // 移除寫死 Margin
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          // 移除 SingleChildScrollView，因為外層已經有了
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).customerSection,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _customerNameController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context).selectCustomer,
                      hintText: 'Click to choose...',
                      prefixIcon: IconText(Icons.person),
                      suffixIcon: IconText(Icons.arrow_drop_down),
                      border: OutlineInputBorder(),
                    ),
                    onTap: _isHistorical
                        ? null
                        : () => _showCustomerSelectSheet(context),
                  ),
                ),
                const SizedBox(width: 8),
                if (!_isHistorical)
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      icon: IconText(
                        Icons.person_add,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      tooltip: AppLocalizations.of(context).addNewCustomer,
                      onPressed: () => _showAddCustomerDialog(context),
                    ),
                  ),
              ],
            ),

            if (_selectedCustomer != null &&
                _selectedCustomer!.measurements.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      _showCustomerMeasurementsDialog(_selectedCustomer!),
                  icon: const IconText(Icons.straighten, size: 16),
                  label: Text(AppLocalizations.of(context).bodyMeasurements),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),
            InkWell(
              onTap: _isHistorical
                  ? null
                  : () async {
                      final cart = context.read<CartProvider>();
                      int maxDays = 7;
                      for (final item in cart.items) {
                        final svc = _serviceByName[item.service];
                        if (svc != null && svc.durationDays > maxDays) {
                          maxDays = svc.durationDays;
                        }
                      }
                      final initial = _deliveryDate ??
                          DateTime.now().add(Duration(days: maxDays));
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: initial,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 1),
                        ),
                        lastDate: DateTime.now().add(
                          const Duration(days: 730),
                        ),
                      );
                      if (picked != null) {
                        setState(() => _deliveryDate = picked);
                      }
                    },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).deliveryDateLabel,
                  prefixIcon: const IconText(Icons.event_outlined),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: _deliveryDate != null && !_isHistorical
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () =>
                              setState(() => _deliveryDate = null),
                        )
                      : null,
                ),
                child: Text(
                  _deliveryDate != null
                      ? DateFormat('yyyy-MM-dd').format(_deliveryDate!)
                      : _isHistorical
                      ? '—'
                      : AppLocalizations.of(context).tapToSet,
                  style: TextStyle(
                    color: _deliveryDate != null
                        ? null
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              readOnly: _isHistorical,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).notesLabel,
                hintText: AppLocalizations.of(context).notesHint,
                prefixIcon: const IconText(Icons.notes_outlined),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
              minLines: 1,
            ),

            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context).depositPaymentMethod,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              initialValue: _selectedPaymentMethod,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _paymentMethods
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: _isHistorical
                  ? null
                  : (v) => setState(() => _selectedPaymentMethod = v!),
            ),

            const SizedBox(height: 24),
            const Divider(),

            _buildRow(AppLocalizations.of(context).subtotal, subtotal),
            const SizedBox(height: 8),
            TextField(
              controller: _discountController,
              readOnly: _isHistorical,
              decoration: const InputDecoration(
                labelText: 'Discount',
                prefixIcon: IconText(Icons.remove_circle_outline, size: 18),
                isDense: true,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            _buildRow(
              AppLocalizations.of(context).total,
              total,
              isBold: true,
              fontSize: 20,
            ),
            const SizedBox(height: 16),
            const Divider(),

            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).costBreakdown,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildRow(
              AppLocalizations.of(context).materialCost,
              materialCost,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 8),
            _buildRow(
              'Outsourcing Cost (Auto)',
              outsourcingCost,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _fixedCostController,
                    readOnly: _isHistorical,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context).fixedCost,
                      prefixIcon: const IconText(Icons.apartment_outlined),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'),
                      ),
                    ],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _laborCostController,
                    readOnly: _isHistorical,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context).laborCost,
                      prefixIcon: const IconText(Icons.build_outlined),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'),
                      ),
                    ],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildRow(
              AppLocalizations.of(context).totalCost,
              totalCost,
              isBold: true,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 8),
            _buildRow(
              AppLocalizations.of(context).estimatedProfit,
              totalProfit,
              isBold: true,
              color: totalProfit >= 0 ? Theme.of(context).colorScheme.tertiary : Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            const Divider(),

            const SizedBox(height: 8),
            TextField(
              controller: _depositController,
              readOnly: _isHistorical,
              decoration: InputDecoration(
                labelText: 'Deposit (Initial)',
                prefixIcon: const IconText(Icons.payments_outlined),
                border: const OutlineInputBorder(),
                fillColor: _isHistorical
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : isEditMode
                    ? Theme.of(context).colorScheme.surfaceContainerLow
                    : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                filled: true,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              onChanged: (_) => setState(() {}),
            ),

            if (isEditMode) ...[
              const SizedBox(height: 16),
              _buildPaymentsSection(),
            ],

            const SizedBox(height: 16),

            Builder(builder: (context) {
              final overpaid = balance < 0 ? -balance : 0.0;
              final displayBalance = balance.clamp(0.0, double.infinity);
              final isPaid = displayBalance <= 0;
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isPaid
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : Theme.of(context).colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isPaid
                        ? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.4)
                        : Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  children: [
                    _buildRow(
                      AppLocalizations.of(context).outstandingBalance,
                      displayBalance,
                      isBold: true,
                      color: isPaid
                          ? Theme.of(context).colorScheme.onSecondaryContainer
                          : Theme.of(context).colorScheme.onTertiaryContainer,
                    ),
                    if (overpaid > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          IconText(
                            Icons.info_outline,
                            size: 13,
                            color: Theme.of(context).colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Overpaid: $_currencySymbol${overpaid.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: cart.items.isEmpty ? null : _processOrder,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  backgroundColor: isEditMode
                      ? Theme.of(context).colorScheme.secondary
                      : Theme.of(context).colorScheme.primary,
                  foregroundColor: isEditMode
                      ? Theme.of(context).colorScheme.onSecondary
                      : Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ), // 按鈕也圓角一點
                ),
                child: Text(
                  btnText,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
    String label,
    double value, {
    bool isBold = false,
    double fontSize = 14,
    Color? color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
        Text(
          '$_currencySymbol${value.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _FabricPreview {
  final OrderItem item;
  final String materialName;
  final String imageUrl;

  const _FabricPreview({
    required this.item,
    required this.materialName,
    required this.imageUrl,
  });
}

class _FabricGalleryDialog extends StatefulWidget {
  final DatabaseService dbService;
  final List<OrderItem> orderItems;
  final OrderItem selectedItem;

  const _FabricGalleryDialog({
    required this.dbService,
    required this.orderItems,
    required this.selectedItem,
  });

  @override
  State<_FabricGalleryDialog> createState() => _FabricGalleryDialogState();
}

class _FabricGalleryDialogState extends State<_FabricGalleryDialog> {
  late Future<List<_FabricPreview>> _previewsFuture;
  PageController? _pageController;
  int _currentPage = 0;
  final TransformationController _transformationController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    _previewsFuture = _loadPreviews();
  }

  @override
  void dispose() {
    _pageController?.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  Future<List<_FabricPreview>> _loadPreviews() async {
    final allMaterials = await widget.dbService.getInventory();
    final materialsById = {
      for (final material in allMaterials) material.id: material,
    };
    final materialsByName = {
      for (final material in allMaterials)
        material.name.trim().toLowerCase(): material,
    };

    final previews = <_FabricPreview>[];
    for (final item in widget.orderItems) {
      MaterialItem? material;
      final fabricId = item.fabricId?.trim() ?? '';
      final fabricName = item.fabricName?.trim().toLowerCase() ?? '';

      if (fabricId.isNotEmpty) {
        material = materialsById[fabricId];
      }
      material ??= materialsByName[fabricName];

      final imageUrl = material?.imageUrl?.trim() ?? '';
      if (imageUrl.isEmpty) {
        continue;
      }

      previews.add(
        _FabricPreview(
          item: item,
          materialName: material?.name ?? item.fabricName ?? 'Fabric',
          imageUrl: imageUrl,
        ),
      );
    }

    return previews;
  }

  int _resolveInitialPage(List<_FabricPreview> previews) {
    final selectedId = widget.selectedItem.id;
    if (selectedId.isNotEmpty) {
      final byId = previews.indexWhere((p) => p.item.id == selectedId);
      if (byId >= 0) return byId;
    }

    final selectedFabricId = widget.selectedItem.fabricId ?? '';
    if (selectedFabricId.isNotEmpty) {
      final byFabricId = previews.indexWhere(
        (p) => p.item.fabricId == selectedFabricId,
      );
      if (byFabricId >= 0) return byFabricId;
    }

    final selectedFabricName = widget.selectedItem.fabricName?.trim() ?? '';
    if (selectedFabricName.isNotEmpty) {
      final byFabricName = previews.indexWhere(
        (p) => (p.item.fabricName?.trim() ?? '') == selectedFabricName,
      );
      if (byFabricName >= 0) return byFabricName;
    }

    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context).fabricImagesTitle),
      content: SizedBox(
        width: 500,
        child: FutureBuilder<List<_FabricPreview>>(
          future: _previewsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 280,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError) {
              return const SizedBox(
                height: 140,
                child: Center(child: Text('Failed to load fabric images.')),
              );
            }

            final previews = snapshot.data ?? const <_FabricPreview>[];
            if (previews.isEmpty) {
              return const SizedBox(
                height: 140,
                child: Center(
                  child: Text('No fabric images available for this order.'),
                ),
              );
            }

            final initialPage = _resolveInitialPage(previews);
            _pageController ??= PageController(initialPage: initialPage);
            if (_currentPage >= previews.length) {
              _currentPage = previews.length - 1;
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  previews[_currentPage].materialName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  previews[_currentPage].item.service,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 340,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: previews.length,
                    onPageChanged: (index) {
                      _transformationController.value = Matrix4.identity();
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      final preview = previews[index];
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow),
                          child: GestureDetector(
                            onDoubleTap: () {
                              _transformationController.value =
                                  Matrix4.identity();
                            },
                            child: InteractiveViewer(
                              transformationController:
                                  _transformationController,
                              minScale: 1,
                              maxScale: 5,
                              child: Image.network(
                                preview.imageUrl,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) {
                                  return const Center(
                                    child: Text(
                                      'Unable to display fabric image.',
                                    ),
                                  );
                                },
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Swipe left/right to view more',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                    Text('${_currentPage + 1} / ${previews.length}'),
                  ],
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context).closeButton),
        ),
      ],
    );
  }
}

/// 揀選未匯入嘅 Bespoke 訂製訂單。
class _BespokeOrderPickerDialog extends StatefulWidget {
  const _BespokeOrderPickerDialog({required this.service});
  final BespokeImportService service;

  @override
  State<_BespokeOrderPickerDialog> createState() =>
      _BespokeOrderPickerDialogState();
}

class _BespokeOrderPickerDialogState extends State<_BespokeOrderPickerDialog> {
  late final Future<List<BespokeOrderSummary>> _future = widget.service
      .fetchPending();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd');
    return AlertDialog(
      title: const Text('從 Bespoke 匯入'),
      content: SizedBox(
        width: 440,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '搜尋客人名稱',
                isDense: true,
                prefixIcon: IconText(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<BespokeOrderSummary>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('載入失敗：${snap.error}'));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final list = snap.data!
                      .where(
                        (o) =>
                            _query.isEmpty ||
                            o.clientName.toLowerCase().contains(_query),
                      )
                      .toList();
                  if (list.isEmpty) {
                    return const Center(child: Text('沒有待匯入的訂製訂單'));
                  }
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final o = list[i];
                      final info = [
                        if (o.garmentLabels.isNotEmpty) o.garmentLabels,
                        if (o.date != null) '落單 ${fmt.format(o.date!)}',
                        if (o.dueDate != null) '交貨 ${fmt.format(o.dueDate!)}',
                      ].join('　');
                      return ListTile(
                        dense: true,
                        title: Text(o.clientName),
                        subtitle: Text(info),
                        trailing: Text(o.totalPrice.toStringAsFixed(0)),
                        onTap: () => Navigator.pop(context, o),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
