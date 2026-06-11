import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/order.dart';
import '../models/workshop_order.dart';
import '../models/workshop_status.dart';
import '../models/customer.dart';
import '../models/material_item.dart';
import '../models/service_item.dart';
import '../services/cost_calculation_service.dart';
import '../services/database_service.dart';
import '../services/pdf_service.dart';
import '../providers/cart_provider.dart';
import '../components/order_item_dialog.dart';

class POSPage extends StatefulWidget {
  final Order? orderForEdit;
  const POSPage({super.key, this.orderForEdit});

  @override
  State<POSPage> createState() => _POSPageState();
}

class _POSPageState extends State<POSPage> {
  final DatabaseService _dbService = DatabaseService();

  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _depositController = TextEditingController();
  final TextEditingController _balancePaymentController = TextEditingController();
  final TextEditingController _fixedCostController = TextEditingController();

  String? _selectedCustomerId;
  Customer? _selectedCustomer;
  Map<String, ServiceItem> _serviceByName = {};

  bool _isLoading = false;
  String _selectedPaymentMethod = 'Cash';
  String _selectedBalancePaymentMethod = 'Cash';

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
  StreamSubscription<List<ServiceItem>>? _servicesSubscription;

  // Completed/cancelled orders keep their original financial values.
  // Confirmed edit orders can still recalculate totals from the latest cart.
  bool get _isHistorical {
    if (widget.orderForEdit == null) return false;
    final status = widget.orderForEdit!.status.toLowerCase();
    return status == 'completed' || status == 'cancelled';
  }

  @override
  void initState() {
    super.initState();
    _timeStream = Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now())
        .asBroadcastStream();
    _customersStream = _dbService.getCustomersStream();
    _dbService.seedDefaultServices();
    _servicesSubscription = _dbService.getServicesStream().listen((services) {
      if (!mounted) return;
      setState(() {
        _serviceByName = {for (final service in services) service.name: service};
      });
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
    _balancePaymentController.dispose();
    _fixedCostController.dispose();
    _servicesSubscription?.cancel();
    super.dispose();
  }

  void _loadExistingOrder(Order order) {
    setState(() {
      context.read<CartProvider>().loadOrderItems(order.items);

      _selectedCustomerId =
          order.customerId.isNotEmpty ? order.customerId : null;
      _customerNameController.text = order.customerName;

      _discountController.text =
          order.discount == 0 ? '' : order.discount.toStringAsFixed(0);
      _depositController.text =
          order.deposit == 0 ? '' : order.deposit.toStringAsFixed(0);
      _fixedCostController.text =
          order.fixedCost == 0 ? '' : order.fixedCost.toStringAsFixed(0);

      _balancePaymentController.text = order.balancePayment == 0
          ? ''
          : order.balancePayment.toStringAsFixed(0);
      if (order.balancePaymentMethod != null &&
          _paymentMethods.contains(order.balancePaymentMethod)) {
        _selectedBalancePaymentMethod = order.balancePaymentMethod!;
      }

      if (_paymentMethods.contains(order.paymentMethod)) {
        _selectedPaymentMethod = order.paymentMethod;
      } else {
        _selectedPaymentMethod = 'Other';
      }
    });
  }

  void _showCustomerSelectSheet(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        String searchQuery = '';
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                          const Text('Select Customer',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search name or phone...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.grey[100],
                        ),
                        onChanged: (val) =>
                            setModalState(() => searchQuery = val.toLowerCase()),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: StreamBuilder<List<Customer>>(
                          stream: _customersStream,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return Center(
                                  child: Text('Error: ${snapshot.error}'));
                            }
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }

                            final allCustomers = snapshot.data ?? [];
                            final filteredCustomers = allCustomers.where((c) {
                              return c.name
                                      .toLowerCase()
                                      .contains(searchQuery) ||
                                  c.phone.contains(searchQuery);
                            }).toList();

                            if (filteredCustomers.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.person_off,
                                        size: 48, color: Colors.grey),
                                    const SizedBox(height: 12),
                                    Text(
                                        'No customer found for "$searchQuery"',
                                        style: const TextStyle(
                                            color: Colors.grey)),
                                    const SizedBox(height: 12),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _showAddCustomerDialog(context,
                                            initialName: searchQuery);
                                      },
                                      icon: const Icon(Icons.person_add),
                                      label:
                                          const Text('Add New Customer'),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return ListView.separated(
                              itemCount: filteredCustomers.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final customer = filteredCustomers[index];
                                final isSelected =
                                    customer.id == _selectedCustomerId;
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isSelected
                                        ? Theme.of(context).primaryColor
                                        : Colors.grey[200],
                                    child: Text(
                                      customer.name.isNotEmpty
                                          ? customer.name[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                          color: isSelected
                                              ? Colors.white
                                              : Colors.black),
                                    ),
                                  ),
                                  title: Text(customer.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  subtitle: Text(customer.phone.isNotEmpty
                                      ? customer.phone
                                      : 'No phone'),
                                  trailing: isSelected
                                      ? Icon(Icons.check_circle,
                                          color: Theme.of(context)
                                              .primaryColor)
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
        title: const Text('Add New Customer'),
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
                        borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Name is required';
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
                        borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: Colors.grey[50],
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
                        borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(value)) {
                        return 'Enter a valid email';
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
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
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
                  if (mounted) {
                    setState(() {
                      _selectedCustomerId = id;
                      _customerNameController.text = nameController.text.trim();
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Customer added successfully'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    Navigator.pop(ctx);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              }
            },
            child: const Text('Add Customer'),
          ),
        ],
      ),
    );
  }

  void _openItemDialog({OrderItem? existingItem, int? index}) {
    showDialog(
      context: context,
      builder: (context) => OrderItemDialog(
        existingItem: existingItem,
        index: index,
      ),
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
        const SnackBar(
          content: Text('Please add items and select a customer'),
          backgroundColor: Colors.red,
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
      final syncedItems = _isHistorical
          ? cart.items
          : CostCalculationService.syncItemsWithServicePrices(
              cart.items,
              serviceByName: serviceByName,
            );
      final subtotal = _isHistorical
          ? widget.orderForEdit!.subtotal
          : CostCalculationService.calculateSubtotalFromItems(
              syncedItems,
              serviceByName: serviceByName,
            );
      final materialCost = _isHistorical
          ? widget.orderForEdit!.materialCost
          : cart.totalCost;
      final laborCost = widget.orderForEdit?.laborCost ?? 0.0;
      final outsourcingCost = _isHistorical
          ? widget.orderForEdit!.outsourcingCost
          : CostCalculationService.calculateOutsourcingCostFromItems(
              syncedItems,
              serviceByName: serviceByName,
            );
      final fixedCost = double.tryParse(_fixedCostController.text) ??
          (_isHistorical ? widget.orderForEdit!.fixedCost : 0.0);
      final totalCost = _isHistorical
          ? widget.orderForEdit!.totalCost
          : CostCalculationService.calculateTotalCost(
              materialCost: materialCost,
              outsourcingCost: outsourcingCost,
              fixedCost: fixedCost,
            );
      final discount = double.tryParse(_discountController.text) ??
          (_isHistorical ? widget.orderForEdit!.discount : 0.0);
      final total = _isHistorical
          ? widget.orderForEdit!.total
          : CostCalculationService.calculateDiscountedTotal(
              subtotal: subtotal,
              discount: discount,
            );

      double deposit = _isHistorical
          ? widget.orderForEdit!.deposit
          : double.tryParse(_depositController.text) ?? 0.0;
      double balancePayment = _isHistorical
          ? widget.orderForEdit!.balancePayment
          : double.tryParse(_balancePaymentController.text) ?? 0.0;
      double balance = _isHistorical
          ? widget.orderForEdit!.balance
          : CostCalculationService.calculateBalance(
              total: total,
              deposit: deposit,
              balancePayment: balancePayment,
            );

      double totalProfit =
          _isHistorical ? widget.orderForEdit!.totalProfit : total - totalCost;
      String orderStatus = _isHistorical
          ? widget.orderForEdit!.status
          : balance <= 0
          ? 'completed'
          : 'confirmed';

      bool isEditMode = widget.orderForEdit != null;
      String orderId = isEditMode ? widget.orderForEdit!.id : '';

      String customerId = '';
      if (_selectedCustomerId != null) {
        customerId = _selectedCustomerId!;
        if (_selectedCustomer != null) {
          await _dbService.updateCustomer(
            _selectedCustomer!.copyWith(
              orders: _selectedCustomer!.orders + 1,
              totalSpent: _selectedCustomer!.totalSpent + total,
            ),
          );
        }
      } else if (!isEditMode && customerId.isEmpty) {
        final newCustomer = Customer(
          id: '',
          name: finalCustomerName,
          email: '',
          phone: '',
          orders: 1,
          totalSpent: total,
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
        balancePaymentMethod: _isHistorical
            ? widget.orderForEdit!.balancePaymentMethod
            : balancePayment > 0
            ? _selectedBalancePaymentMethod
            : null,
        balancePaidDate: _isHistorical
            ? widget.orderForEdit!.balancePaidDate
            : balancePayment > 0
            ? DateTime.now()
            : widget.orderForEdit?.balancePaidDate,
        balance: balance,
        materialCost: materialCost,
        laborCost: laborCost,
        outsourcingCost: outsourcingCost,
        fixedCost: fixedCost,
        totalCost: totalCost,
        totalProfit: totalProfit,
        status: orderStatus,
        paymentMethod: _isHistorical
            ? widget.orderForEdit!.paymentMethod
            : _selectedPaymentMethod,
        createdAt: isEditMode ? widget.orderForEdit!.createdAt : DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Order object for printing (will be updated with ID after save)
      Order orderForPrinting = orderData;
      // Collect generated workshop orders for job ticket printing
      List<WorkshopOrder> generatedTickets = [];

      if (isEditMode) {
        await _dbService.updateOrder(orderData);
      } else {
        orderId = await _dbService.addOrder(orderData);
        orderForPrinting = orderData.copyWith(id: orderId);

        for (var item in syncedItems) {
          if (item.fabricUsed > 0 || item.service == 'Alterations') {
            // Look up service duration from settings
            int productionDays = 7; // Default fallback
            try {
              final serviceSettings = allServices.firstWhere(
                (s) => s.name == item.service,
              );
              productionDays = serviceSettings.durationDays;
            } catch (_) {
              // Service not found in settings, use default
              print(
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

            await _dbService.addWorkshopOrder(ticket);
            generatedTickets.add(ticket);
          }
        }
      }

      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order processed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // === Step 4: Ask to print receipt ===
      if (mounted) {
        bool? printReceipt = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Print Receipt?'),
            content: const Text(
              'Do you want to print the customer receipt now?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('No'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Print'),
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
            title: const Text('Print Job Tickets?'),
            content: Text(
              'Created ${generatedTickets.length} workshop orders.\nPrint job tickets for the factory?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('No'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Print'),
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
        final fabricItems = cart.items.where((item) =>
            (item.fabricId ?? '').trim().isNotEmpty ||
            (item.fabricName ?? '').trim().isNotEmpty ||
            item.fabricUsed > 0).toList();

        if (fabricItems.isNotEmpty) {
          final markOrdered = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('訂布提醒'),
              content: const Text('此訂單包含需要布料的項目。是否已完成訂購布料？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('稍後處理'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('已訂布料'),
                ),
              ],
            ),
          );

          if (markOrdered == true) {
            await _dbService.updateOrderFabricRequiredItemsStatus(
              orderId: orderId,
              isFabricOrdered: true,
            );
            await _dbService.updateWorkshopOrdersFabricStatus(
              orderId: orderId,
              isFabricOrdered: true,
            );
          }
        }
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
            _balancePaymentController.clear();
            _fixedCostController.clear();
            _selectedCustomer = null;
            _selectedCustomerId = null;
            _selectedPaymentMethod = 'Cash';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
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
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.brown,
        ),
      );
      appBarColor = Colors.orange[100];
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
                    const Text(
                      'Cart Items',
                      style: TextStyle(
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
                              style: TextStyle(color: Colors.grey[600]),
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
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Cart is empty',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () => _openItemDialog(),
                          icon: const Icon(Icons.add),
                          label: const Text('Add First Item'),
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
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final item = cart.items[index];
                      final unitPrice = _isHistorical
                          ? item.price
                          : CostCalculationService.resolveUnitPrice(
                              item,
                              serviceByName: _serviceByName,
                            );
                      final hasFabricReference =
                          (item.fabricId ?? '').trim().isNotEmpty ||
                          (item.fabricName ?? '').trim().isNotEmpty ||
                          item.fabricUsed > 0;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
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
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'x${item.quantity}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: item.fabricName != null
                            ? Text(
                                '${item.fabricName} (${item.fabricUsed}m)\nCost: \$${item.cost.toStringAsFixed(1)}',
                              )
                            : const Text('No fabric required'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '\$${(unitPrice * item.quantity).toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (hasFabricReference) ...[
                              IconButton(
                                icon: const Icon(
                                  Icons.image_outlined,
                                  color: Colors.teal,
                                ),
                                tooltip: 'Preview fabric images',
                                onPressed: () => _showFabricImageDialog(
                                  orderItems: cart.items,
                                  selectedItem: item,
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            // 編輯按鈕
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              tooltip: 'Edit Item',
                              onPressed: () => _openItemDialog(
                                existingItem: item,
                                index: index,
                              ),
                            ),
                            // Delete via Provider
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => cart.removeItem(index),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _openItemDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Item'),
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

  Widget _buildSummaryCard() {
    final cart = context.watch<CartProvider>();

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
    double fixedCost = double.tryParse(_fixedCostController.text) ??
        (_isHistorical ? widget.orderForEdit!.fixedCost : 0.0);
    double totalCost = _isHistorical
        ? widget.orderForEdit!.totalCost
        : CostCalculationService.calculateTotalCost(
            materialCost: materialCost,
            outsourcingCost: outsourcingCost,
            fixedCost: fixedCost,
          );
    double discount = double.tryParse(_discountController.text) ??
        (_isHistorical ? widget.orderForEdit!.discount : 0.0);
    double total = _isHistorical
        ? widget.orderForEdit!.total
        : CostCalculationService.calculateDiscountedTotal(
            subtotal: subtotal,
            discount: discount,
          );
    double totalProfit =
        _isHistorical ? widget.orderForEdit!.totalProfit : total - totalCost;

    double deposit = double.tryParse(_depositController.text) ?? 0.0;
    double balancePayment =
        double.tryParse(_balancePaymentController.text) ?? 0.0;
    double balance = CostCalculationService.calculateBalance(
      total: total,
      deposit: deposit,
      balancePayment: balancePayment,
    );

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
            const Text(
              'Customer',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _customerNameController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Select Customer',
                      hintText: 'Click to choose...',
                      prefixIcon: Icon(Icons.person),
                      suffixIcon: Icon(Icons.arrow_drop_down),
                      border: OutlineInputBorder(),
                    ),
                    onTap: () => _showCustomerSelectSheet(context),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: Icon(
                      Icons.person_add,
                      color: Theme.of(context).primaryColor,
                    ),
                    tooltip: 'Add New Customer',
                    onPressed: () => _showAddCustomerDialog(context),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            const Text(
              'Deposit Payment Method',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              value: _selectedPaymentMethod,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _paymentMethods
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedPaymentMethod = v!),
            ),

            const SizedBox(height: 24),
            const Divider(),

            _buildRow('Subtotal', subtotal),
            const SizedBox(height: 8),
            TextField(
              controller: _discountController,
              decoration: const InputDecoration(
                labelText: 'Discount',
                prefixIcon: Icon(Icons.remove_circle_outline, size: 18),
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
            _buildRow('Total', total, isBold: true, fontSize: 20),
            const SizedBox(height: 16),
            const Divider(),

            const SizedBox(height: 8),
            const Text(
              'Cost Breakdown',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildRow(
              'Material Cost',
              materialCost,
              color: Colors.grey[700],
            ),
            const SizedBox(height: 8),
            _buildRow(
              'Outsourcing Cost',
              outsourcingCost,
              color: Colors.grey[700],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _fixedCostController,
              readOnly: _isHistorical,
              decoration: const InputDecoration(
                labelText: 'Fixed Cost',
                prefixIcon: Icon(Icons.apartment_outlined),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            _buildRow(
              'Total Cost',
              totalCost,
              isBold: true,
              color: Colors.red[400],
            ),
            const SizedBox(height: 8),
            _buildRow(
              'Estimated Profit',
              totalProfit,
              isBold: true,
              color: totalProfit >= 0 ? Colors.green[700] : Colors.red[700],
            ),
            const SizedBox(height: 16),
            const Divider(),

            const SizedBox(height: 8),
            TextField(
              controller: _depositController,
              decoration: InputDecoration(
                labelText: 'Deposit (Initial)',
                prefixIcon: const Icon(Icons.payments_outlined),
                border: const OutlineInputBorder(),
                fillColor: isEditMode
                    ? Colors.grey[100]
                    : const Color(0xFFF0F9EB),
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Balance Payment (Pay Now)',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _balancePaymentController,
                      decoration: const InputDecoration(
                        hintText: 'Enter amount',
                        prefixIcon: Icon(Icons.add_card, color: Colors.blue),
                        border: OutlineInputBorder(),
                        isDense: true,
                        fillColor: Colors.white,
                        filled: true,
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
                    const SizedBox(height: 12),
                    const Text(
                      'Balance Method',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      value: _selectedBalancePaymentMethod,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        fillColor: Colors.white,
                        filled: true,
                      ),
                      items: _paymentMethods
                          .map(
                            (m) => DropdownMenuItem(value: m, child: Text(m)),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _selectedBalancePaymentMethod = v!),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: balance > 0 ? Colors.orange[50] : Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: balance > 0 ? Colors.orange[200]! : Colors.green[200]!,
                ),
              ),
              child: _buildRow(
                'Outstanding Balance',
                balance,
                isBold: true,
                color: balance > 0 ? Colors.deepOrange : Colors.green[700],
              ),
            ),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: cart.items.isEmpty ? null : _processOrder,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  backgroundColor: isEditMode
                      ? Colors.orange
                      : Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
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
          '\$${value.toStringAsFixed(0)}',
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
      title: const Text('Fabric Images'),
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
                  style: TextStyle(color: Colors.grey[700]),
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
                        borderRadius: BorderRadius.circular(8),
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Colors.grey[100]),
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
                      style: TextStyle(color: Colors.grey[700]),
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
          child: const Text('Close'),
        ),
      ],
    );
  }
}
