import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/order.dart';
import '../models/workshop_order.dart';
import '../models/workshop_status.dart';
import '../models/customer.dart';
import '../models/material_item.dart';
import '../models/service_item.dart';
import '../services/database_service.dart';
import '../services/pdf_service.dart';

class POSPage extends StatefulWidget {
  final Order? orderForEdit;

  const POSPage({super.key, this.orderForEdit});

  @override
  State<POSPage> createState() => _POSPageState();
}

class _POSPageState extends State<POSPage> {
  final DatabaseService _dbService = DatabaseService();

  List<OrderItem> _items = [];
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _depositController = TextEditingController();
  final TextEditingController _balancePaymentController =
      TextEditingController();

  bool _isLoading = false;
  String _selectedPaymentMethod = 'Cash';
  String _selectedBalancePaymentMethod = 'Cash';

  String? _selectedCustomerId;
  Customer? _selectedCustomer;

  late Stream<DateTime> _timeStream;
  late Stream<List<Customer>> _customersStream;
  Stream<int>? _nextOrderIdStream;

  final List<String> _paymentMethods = [
    'Cash',
    'Visa',
    'Master',
    'AE',
    'Cup',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _timeStream = Stream.periodic(
      const Duration(seconds: 1),
      (_) => DateTime.now(),
    ).asBroadcastStream();
    _customersStream = _dbService.getCustomersStream();

    // Ensure there are default service data (prevent empty on first open)
    _dbService.seedDefaultServices();

    if (widget.orderForEdit != null) {
      _loadExistingOrder(widget.orderForEdit!);
    } else {
      _nextOrderIdStream = _dbService.getNextOrderIdStream();
    }
  }

  void _loadExistingOrder(Order order) {
    setState(() {
      _items = List.from(order.items);
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

  @override
  void dispose() {
    _customerNameController.dispose();
    _discountController.dispose();
    _depositController.dispose();
    _balancePaymentController.dispose();
    super.dispose();
  }

  // === 核心功能：可搜尋的客戶選擇視窗 ===
  void _showCustomerSelectSheet(BuildContext context) {
    showDialog(
      // 改用 showDialog
      context: context,
      builder: (context) {
        String searchQuery = '';

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 500,
              maxHeight: 600,
            ), // 限制大小
            child: StatefulBuilder(
              // 需要 StatefulBuilder 來更新搜尋結果
              builder: (BuildContext context, StateSetter setModalState) {
                return Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Select Customer',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 搜尋框
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search name or phone...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[100],
                        ),
                        onChanged: (val) => setModalState(
                          () => searchQuery = val.toLowerCase(),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 客戶列表
                      Expanded(
                        child: StreamBuilder<List<Customer>>(
                          stream: _customersStream,
                          builder: (context, snapshot) {
                            if (snapshot.hasError)
                              return Center(
                                child: Text('Error: ${snapshot.error}'),
                              );
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
                                    const Icon(
                                      Icons.person_off,
                                      size: 48,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No customer found for "$searchQuery"',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.pop(context); // 關閉選擇視窗
                                        _showAddCustomerDialog(
                                          context,
                                          initialName: searchQuery,
                                        ); // 開啟新增視窗
                                      },
                                      icon: const Icon(Icons.person_add),
                                      label: const Text('Add New Customer'),
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
                                            : Colors.black,
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
                                      ? Icon(
                                          Icons.check_circle,
                                          color: Theme.of(context).primaryColor,
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
    final nameCtrl = TextEditingController(text: initialName);
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New Customer'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (v) => v!.isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phoneCtrl,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
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
                    name: nameCtrl.text.trim(),
                    phone: phoneCtrl.text.trim(),
                    email: emailCtrl.text.trim(),
                    orders: 0,
                    totalSpent: 0,
                  );
                  String newId = await _dbService.addCustomer(newCustomer);

                  if (mounted) {
                    Navigator.pop(ctx);
                    setState(() {
                      _selectedCustomerId = newId;
                      _customerNameController.text = newCustomer.name;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Customer added: ${newCustomer.name}'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // === 優化：通用項目對話框 (支援新增與修改) ===
  void _showItemDialog({OrderItem? existingItem, int? index}) async {
    // 1. 讀取服務與庫存資料
    final services = await _dbService.getServicesStream().first;
    final fabrics = await _dbService.getInventory();

    if (!mounted) return;

    // 2. 初始化控制器 (若為編輯模式，填入現有數值)
    final priceController = TextEditingController(
      text: existingItem?.price.toStringAsFixed(0) ?? '',
    );
    final usageController = TextEditingController(
      text: existingItem?.fabricUsed.toString() ?? '0',
    );
    final quantityController = TextEditingController(
      text: existingItem?.quantity.toString() ?? '1',
    );
    final suggestedPriceController = TextEditingController();

    // 3. 設定初始選取狀態
    ServiceItem? selectedService;
    MaterialItem? selectedFabric;

    if (existingItem != null) {
      // 嘗試還原已選的服務
      try {
        selectedService = services.firstWhere(
          (s) => s.name == existingItem.service,
        );
      } catch (_) {}

      // 嘗試還原已選的布料
      if (existingItem.fabricId != null) {
        try {
          selectedFabric = fabrics.firstWhere(
            (f) => f.id == existingItem.fabricId,
          );
        } catch (_) {}
      }
    }

    // 4. 定義計算邏輯 (用於即時更新建議價格)
    void calculateValues() {
      if (selectedService != null) {
        double servicePrice = selectedService!.price;
        double fabricUnitCost = selectedFabric?.costPerUnit ?? 0.0;
        double currentUsage = double.tryParse(usageController.text) ?? 0.0;

        double totalFabricCost = fabricUnitCost * currentUsage;
        double suggestedPrice = (servicePrice + totalFabricCost) * 2.5;

        suggestedPriceController.text = suggestedPrice.toStringAsFixed(0);

        // 僅在價格欄位為空 (新增模式) 時才自動填入，避免覆蓋使用者輸入
        if (priceController.text.isEmpty) {
          priceController.text = suggestedPrice.toStringAsFixed(0);
        }
      }
    }

    // 若為編輯模式，先執行一次計算以顯示建議價格參考
    if (existingItem != null) {
      calculateValues();
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          double currentUsage = double.tryParse(usageController.text) ?? 0.0;
          double estimatedMaterialCost = 0;

          if (selectedService != null && selectedFabric != null) {
            estimatedMaterialCost = currentUsage * selectedFabric!.costPerUnit;
          }

          return AlertDialog(
            title: Text(existingItem != null ? 'Edit Item' : 'Add Item'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- 服務選擇 ---
                  if (services.isEmpty)
                    const Text('No services defined.')
                  else
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: services.map((service) {
                        final isSelected = selectedService?.id == service.id;
                        return ChoiceChip(
                          label: Text('${service.name}'),
                          selected: isSelected,
                          onSelected: (selected) {
                            setDialogState(() {
                              selectedService = selected ? service : null;
                              if (selected) {
                                // 若切換服務且用量為0，帶入預設用量
                                if (usageController.text == '0') {
                                  usageController.text = service
                                      .defaultFabricUsage
                                      .toString();
                                }
                                // 若無預設用量，清空布料選取
                                if (service.defaultFabricUsage == 0) {
                                  selectedFabric = null;
                                }
                                // 若為新增模式，重置價格
                                if (existingItem == null)
                                  priceController.clear();
                                calculateValues();
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 16),

                  // --- 布料選擇 ---
                  if (selectedService != null &&
                      (selectedService!.defaultFabricUsage > 0 ||
                          (existingItem?.fabricUsed ?? 0) > 0)) ...[
                    DropdownButtonFormField<MaterialItem>(
                      decoration: const InputDecoration(
                        labelText: 'Select Fabric',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      isExpanded: true,
                      itemHeight: 60,
                      value: selectedFabric,
                      items: fabrics
                          .map(
                            (f) => DropdownMenuItem(
                              value: f,
                              child: Text(
                                '${f.name} (\$${f.costPerUnit.toStringAsFixed(0)})',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setDialogState(() {
                        selectedFabric = value;
                        calculateValues();
                      }),
                    ),
                    const SizedBox(height: 16),
                    // 布料用量
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: usageController,
                            decoration: const InputDecoration(
                              labelText: 'Usage (m)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) {
                              setDialogState(() {}); // 更新預估成本
                              calculateValues();
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Est. Cost',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              '\$${estimatedMaterialCost.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],

                  // --- 價格與數量 ---
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: priceController,
                          decoration: const InputDecoration(
                            labelText: 'Unit Price',
                            prefixIcon: Icon(Icons.attach_money),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: TextFormField(
                          controller: quantityController,
                          decoration: const InputDecoration(
                            labelText: 'Qty',
                            prefixIcon: Icon(Icons.numbers),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: (selectedService == null)
                    ? null
                    : () {
                        // 儲存邏輯
                        final double finalPrice =
                            double.tryParse(priceController.text) ??
                            selectedService!.price;
                        final double finalUsage =
                            double.tryParse(usageController.text) ?? 0.0;
                        final int finalQty =
                            int.tryParse(quantityController.text) ?? 1;

                        final newItem = OrderItem(
                          id:
                              existingItem?.id ??
                              DateTime.now().millisecondsSinceEpoch
                                  .toString(), // 保留舊ID或生成新ID
                          service: selectedService!.name,
                          price: finalPrice,
                          quantity: finalQty,
                          fabricId: selectedFabric?.id,
                          fabricName: selectedFabric?.name,
                          fabricUsed: finalUsage,
                          cost: estimatedMaterialCost,
                        );

                        setState(() {
                          if (existingItem != null && index != null) {
                            // 修改模式：更新清單
                            _items[index] = newItem;
                          } else {
                            // 新增模式：加入清單
                            _items.add(newItem);
                          }
                        });
                        Navigator.pop(context);
                      },
                child: Text(existingItem != null ? 'Save' : 'Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  // === Order Processing with Receipt and Job Ticket Printing ===
  Future<void> _processOrder() async {
    String finalCustomerName = _customerNameController.text.trim();

    if (_items.isEmpty ||
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
      double subtotal = _items.fold(
        0,
        (sum, item) => sum + (item.price * item.quantity),
      );
      double totalCost = _items.fold(
        0,
        (sum, item) => sum + (item.cost * item.quantity),
      );
      double discount = double.tryParse(_discountController.text) ?? 0.0;
      double total = (subtotal - discount).clamp(0, double.infinity);

      double deposit = double.tryParse(_depositController.text) ?? 0.0;
      double balancePayment =
          double.tryParse(_balancePaymentController.text) ?? 0.0;
      double balance = total - (deposit + balancePayment);
      if (balance < 0) balance = 0;

      double totalProfit = total - totalCost;
      String orderStatus = balance <= 0 ? 'completed' : 'confirmed';

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
        items: _items,
        subtotal: subtotal,
        discount: discount,
        total: total,
        deposit: deposit,
        balancePayment: balancePayment,
        balancePaymentMethod: balancePayment > 0
            ? _selectedBalancePaymentMethod
            : null,
        balancePaidDate: balancePayment > 0
            ? DateTime.now()
            : widget.orderForEdit?.balancePaidDate,
        balance: balance,
        totalCost: totalCost,
        totalProfit: totalProfit,
        status: orderStatus,
        paymentMethod: _selectedPaymentMethod,
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

        // Fetch all service settings to enable duration lookup
        final allServices = await _dbService.getServicesStream().first;

        for (var item in _items) {
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

      // === Step 6: Cleanup and navigation ===
      if (mounted) {
        if (isEditMode) {
          Navigator.pop(context);
        } else {
          setState(() {
            _items.clear();
            _customerNameController.clear();
            _discountController.clear();
            _depositController.clear();
            _balancePaymentController.clear();
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

  // 為了適應新佈局，微調 Card 的邊距設定 (移除原本寫死的 margin)
  Widget _buildCartCard() {
    return Card(
      // margin: const EdgeInsets.all(16), // 移除這行，改由外部 Padding 控制
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min, // 讓高度自適應內容
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Cart Items',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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

            if (_items.isEmpty)
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
                      style: TextStyle(color: Colors.grey[500], fontSize: 18),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => _showItemDialog(),
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
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Row(
                      children: [
                        Text(
                          item.service,
                          style: const TextStyle(fontWeight: FontWeight.bold),
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
                          '\$${(item.price * item.quantity).toStringAsFixed(0)}', // 顯示總價 (單價x數量)
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 編輯按鈕
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          tooltip: 'Edit Item',
                          onPressed: () =>
                              _showItemDialog(existingItem: item, index: index),
                        ),
                        // 刪除按鈕
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () =>
                              setState(() => _items.removeAt(index)),
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
                  onPressed: () => _showItemDialog(), // 呼叫新方法 (無參數=新增)
                  icon: const Icon(Icons.add),
                  label: const Text('Add Item'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 微調 Summary Card
  Widget _buildSummaryCard() {
    double subtotal = _items.fold(
      0,
      (sum, item) => sum + (item.price * item.quantity),
    );
    double discount = double.tryParse(_discountController.text) ?? 0.0;
    double total = (subtotal - discount).clamp(0, double.infinity);

    double deposit = double.tryParse(_depositController.text) ?? 0.0;
    double balancePayment =
        double.tryParse(_balancePaymentController.text) ?? 0.0;
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
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
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
                onPressed: _items.isEmpty ? null : _processOrder,
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
