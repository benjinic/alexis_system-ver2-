import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../components/icon_text.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/settings_service.dart';
import '../services/database_service.dart';
import '../services/pdf_service.dart';
import '../models/service_item.dart';
import '../models/workshop_order.dart';
import '../models/workshop_status.dart';
import '../l10n/app_localizations.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsService _settingsService = SettingsService();
  final DatabaseService _dbService = DatabaseService();
  final PdfService _pdfService = PdfService();

  static const List<Color> _accentOptions = [
    Color(0xFF64B5F6),
    Color(0xFFFFB74D),
    Color(0xFF81C784),
    Color(0xFFCE93D8),
    Colors.white,
  ];
  static const List<Color> _textColorOptions = [
    Colors.white,
    Color(0xFFE0E0E0),
    Color(0xFFBDBDBD),
    Color(0xFFFFF9C4),
    Color(0xFFB3E5FC),
  ];

  // 預設值
  String _currency = 'USD';
  String _language = 'English';
  String _unit = 'Meters';
  bool _enableNotifications = true;
  Color _accentColor = const Color(0xFF64B5F6);
  Color _textColor = Colors.white;
  Color _headingTextColor = Colors.white;
  Color _cardTitleColor = Colors.white;
  Color _sidebarTextColor = Colors.white;

  final TextEditingController _shopNameController = TextEditingController();
  final TextEditingController _orderIdController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  final List<String> _languages = ['English', '繁體中文', '简体中文', '日本語'];

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _loadCurrentOrderNumber();
  }

  // 讀取本地設定
  Future<void> _loadPreferences() async {
    final settings = await _settingsService.loadSettings();
    if (!mounted) return;

    setState(() {
      _shopNameController.text = settings['shopName'];
      _currency = settings['currency'];
      _language = settings['language'];
      _unit = settings['unit'];
      _enableNotifications = settings['notifications'];
      _accentColor = Color(settings['accentColor']);
      _textColor = Color(settings['textColor']);
      _headingTextColor = Color(settings['headingTextColor']);
      _cardTitleColor = Color(settings['cardTitleColor']);
      _sidebarTextColor = Color(settings['sidebarTextColor']);
      _isLoading = false;
    });
  }

  Future<void> _updateAccentColor(Color color) async {
    setState(() {
      _accentColor = color;
    });
    await _settingsService.setAccentColor(color.toARGB32());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Accent color saved'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _updateTextColor(Color color) async {
    setState(() {
      _textColor = color;
    });
    await _settingsService.setTextColor(color.toARGB32());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Text color saved'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _updateHeadingTextColor(Color color) async {
    setState(() {
      _headingTextColor = color;
    });
    await _settingsService.setHeadingTextColor(color.toARGB32());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Heading color saved'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _updateCardTitleColor(Color color) async {
    setState(() {
      _cardTitleColor = color;
    });
    await _settingsService.setCardTitleColor(color.toARGB32());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Card & label color saved'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _updateSidebarTextColor(Color color) async {
    setState(() {
      _sidebarTextColor = color;
    });
    await _settingsService.setSidebarTextColor(color.toARGB32());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sidebar color saved'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // 讀取雲端訂單號碼
  Future<void> _loadCurrentOrderNumber() async {
    final nextId = await _dbService.getNextOrderIdStream().first;
    if (!mounted) return;
    setState(() {
      _orderIdController.text = nextId.toString();
    });
  }

  // 更新訂單號碼
  Future<void> _updateOrderNumber() async {
    final newId = int.tryParse(_orderIdController.text);
    if (newId != null && newId > 0) {
      await _dbService.setNextOrderNumber(newId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Next Order ID set to #$newId'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid Order ID'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveAllSettings() async {
    final orderText = _orderIdController.text.trim();
    final parsedOrderId = int.tryParse(orderText);

    if (orderText.isNotEmpty && (parsedOrderId == null || parsedOrderId <= 0)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid Order ID'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await Future.wait([
        _settingsService.setShopName(_shopNameController.text.trim()),
        _settingsService.setCurrency(_currency),
        _settingsService.setLanguage(_language),
        _settingsService.setUnit(_unit),
        _settingsService.setNotifications(_enableNotifications),
        _settingsService.setAccentColor(_accentColor.toARGB32()),
        _settingsService.setTextColor(_textColor.toARGB32()),
        _settingsService.setHeadingTextColor(_headingTextColor.toARGB32()),
        _settingsService.setCardTitleColor(_cardTitleColor.toARGB32()),
        _settingsService.setSidebarTextColor(_sidebarTextColor.toARGB32()),
      ]);

      if (parsedOrderId != null) {
        await _dbService.setNextOrderNumber(parsedOrderId);
      }

      // Reload from persisted sources to ensure UI matches actual saved values.
      await _loadPreferences();
      await _loadCurrentOrderNumber();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).settingsSaved),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save settings: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // === 新增功能：開啟服務管理視窗 ===
  void _showServicesManager(BuildContext context) {
    showDialog(
      // 改用 showDialog
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Manage Services',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const IconText(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Service List
                Expanded(
                  child: StreamBuilder<List<ServiceItem>>(
                    stream: _dbService.getServicesStream(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final services = snapshot.data ?? [];

                      if (services.isEmpty) {
                        return const Center(
                          child: Text('No services found. Add one!'),
                        );
                      }

                      return ListView.separated(
                        itemCount: services.length,
                        separatorBuilder: (_, separatorIndex) =>
                            const Divider(),
                        itemBuilder: (context, index) {
                          final item = services[index];
                          final outsourcingCost = item.outsourcingCost;
                          final hasOutsourcingCost =
                              outsourcingCost != null && outsourcingCost >= 0;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue[50],
                              child: const IconText(
                                Icons.checkroom,
                                color: Colors.blue,
                              ),
                            ),
                            title: Text(
                              item.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              'Price: \$${item.price.toStringAsFixed(0)} / ${item.durationDays} days\n'
                              'Outsource: ${hasOutsourcingCost ? '\$${outsourcingCost.toStringAsFixed(0)}' : 'Not set'}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!hasOutsourcingCost)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 4.0),
                                    child: Tooltip(
                                      message:
                                          'Outsourcing cost is not configured',
                                      child: IconText(
                                        Icons.warning_amber_rounded,
                                        color: Colors.orange,
                                      ),
                                    ),
                                  ),
                                IconButton(
                                  icon: const IconText(
                                    Icons.edit,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () => _showServiceEditDialog(
                                    context,
                                    item: item,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                // Add Button Area
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showServiceEditDialog(context),
                      icon: const IconText(Icons.add),
                      label: const Text('Add New Service'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // === 新增功能：開啟體型欄位管理視窗 ===
  void _showMeasurementFieldsManager(BuildContext context) {
    final textController = TextEditingController(); // 用於新增欄位

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Measurement Fields',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const IconText(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(),

                  // List of Fields
                  Expanded(
                    child: StreamBuilder<List<String>>(
                      stream: _dbService.getMeasurementFieldsStream(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Text('Error: ${snapshot.error}');
                        }
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final fields = snapshot.data ?? [];

                        return ListView.builder(
                          itemCount: fields.length,
                          itemBuilder: (context, index) {
                            return ListTile(
                              dense: true,
                              title: Text(fields[index]),
                              trailing: IconButton(
                                icon: const IconText(
                                  Icons.delete,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                onPressed: () async {
                                  // 刪除邏輯
                                  final newFields = List<String>.from(fields);
                                  newFields.removeAt(index);
                                  await _dbService.updateMeasurementFields(
                                    newFields,
                                  );
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),

                  const Divider(),

                  // Add New Field Input
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: textController,
                          decoration: const InputDecoration(
                            hintText: 'New Field Name (e.g. Wrist)',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          inputFormatters: [
                            TextInputFormatter.withFunction(
                              (oldValue, newValue) => newValue.copyWith(
                                text: newValue.text.toUpperCase(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          if (textController.text.trim().isNotEmpty) {
                            // 新增邏輯 (先讀取舊的，再加入新的)
                            final currentFields = await _dbService
                                .getMeasurementFieldsStream()
                                .first;
                            final newFields = List<String>.from(currentFields);

                            // 避免重複
                            if (!newFields.contains(
                              textController.text.trim(),
                            )) {
                              newFields.add(textController.text.trim());
                              await _dbService.updateMeasurementFields(
                                newFields,
                              );
                              textController.clear(); // 清空輸入框
                            }
                          }
                        },
                        child: const Text('Add'),
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

  // === 新增功能：新增/編輯服務對話框 ===
  void _showServiceEditDialog(BuildContext context, {ServiceItem? item}) {
    final nameCtrl = TextEditingController(text: item?.name ?? '');
    final priceCtrl = TextEditingController(
      text: item?.price.toStringAsFixed(0) ?? '',
    );
    final usageCtrl = TextEditingController(
      text: item?.defaultFabricUsage.toString() ?? '0',
    );
    // New: Duration controller
    final daysCtrl = TextEditingController(
      text: item?.durationDays.toString() ?? '7',
    );
    final outsourcingCtrl = TextEditingController(
      text: item?.outsourcingCost?.toStringAsFixed(0) ?? '',
    );
    final isEditing = item != null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEditing ? 'Edit Service' : 'New Service'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Service Name (e.g. Suit)',
                  border: OutlineInputBorder(),
                ),
                inputFormatters: [
                  TextInputFormatter.withFunction(
                    (oldValue, newValue) =>
                        newValue.copyWith(text: newValue.text.toUpperCase()),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                // Display price and duration side by side
                children: [
                  Expanded(
                    child: TextField(
                      controller: priceCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Price',
                        prefixText: '\$ ',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: daysCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Duration',
                        suffixText: 'Days',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: usageCtrl,
                decoration: InputDecoration(
                  labelText: 'Default Fabric Usage',
                  suffixText: _unit,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: outsourcingCtrl,
                decoration: const InputDecoration(
                  labelText: 'Outsourcing Cost (per item)',
                  prefixText: '\$ ',
                  hintText: 'Leave blank if none',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (isEditing)
            TextButton(
              onPressed: () async {
                // 刪除確認
                final confirm = await showDialog<bool>(
                  context: ctx,
                  builder: (c) => AlertDialog(
                    title: const Text('Delete Service?'),
                    content: Text(
                      'Are you sure you want to delete "${item.name}"?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text(
                          'Delete',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await _dbService.deleteService(item.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final price = double.tryParse(priceCtrl.text) ?? 0.0;
              final usage = double.tryParse(usageCtrl.text) ?? 0.0;
              final days = int.tryParse(daysCtrl.text) ?? 7; // Get input days
              final outsourcingCostInput = outsourcingCtrl.text.trim();
              final messenger = ScaffoldMessenger.of(this.context);

              if (name.isEmpty) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Service name cannot be empty.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              if (outsourcingCostInput.isNotEmpty &&
                  double.tryParse(outsourcingCostInput) == null) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Outsourcing cost must be a valid number.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              final outsourcingCost = outsourcingCostInput.isEmpty
                  ? null
                  : double.tryParse(outsourcingCostInput);

              final newItem = ServiceItem(
                id: item?.id ?? '',
                name: name,
                price: price,
                defaultFabricUsage: usage,
                durationDays: days, // Save duration
                outsourcingCost: outsourcingCost,
              );

              try {
                String savedServiceId = item?.id ?? '';
                if (isEditing) {
                  await _dbService.updateService(newItem);
                } else {
                  savedServiceId = await _dbService.addService(newItem);
                }

                final savedService = await _dbService.getServiceById(
                  savedServiceId,
                );
                if (savedService == null) {
                  throw Exception(
                    'Write succeeded but read-back returned no data.',
                  );
                }

                const tolerance = 0.001;
                final isNameMatched = savedService.name.trim() == name;
                final isPriceMatched =
                    (savedService.price - price).abs() < tolerance;
                final isUsageMatched =
                    (savedService.defaultFabricUsage - usage).abs() < tolerance;
                final isDaysMatched = savedService.durationDays == days;
                final savedOutsource = savedService.outsourcingCost;
                final isOutsourceMatched =
                    (savedOutsource == null && outsourcingCost == null) ||
                    (savedOutsource != null &&
                        outsourcingCost != null &&
                        (savedOutsource - outsourcingCost).abs() < tolerance);

                if (!isNameMatched ||
                    !isPriceMatched ||
                    !isUsageMatched ||
                    !isDaysMatched ||
                    !isOutsourceMatched) {
                  throw Exception(
                    'Read-back mismatch. Saved: '
                    'name=${savedService.name}, '
                    'price=${savedService.price.toStringAsFixed(2)}, '
                    'usage=${savedService.defaultFabricUsage.toStringAsFixed(2)}, '
                    'days=${savedService.durationDays}, '
                    'outsource=${savedOutsource?.toStringAsFixed(2) ?? 'null'}',
                  );
                }

                if (ctx.mounted) Navigator.pop(ctx);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      '${isEditing ? 'Service updated' : 'Service added'} and verified. '
                      'Read-back outsource: '
                      '${savedOutsource == null ? 'Not set' : '\$${savedOutsource.toStringAsFixed(0)}'}',
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Save to Firebase failed: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text(isEditing ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
  }

  // === PDF Printing Test ===
  Future<void> _handleTestPrint() async {
    final dummyOrder = WorkshopOrder(
      id: 'TEST-ID-12345',
      orderId: '14099',
      customer: 'Chan Tai Man (Test)',
      item: '3-Piece Suit (VBC 110s)',
      status: WorkshopStatus.cutting,
      priority: 'urgent',
      dueDate: DateTime.now().add(const Duration(days: 14)),
      progress: 0,
      notes:
          'This is a test print.\n- Jacket: Half lined\n- Trousers: No pleats\n- Waist: Side adjusters',
      createdAt: DateTime.now(),
    );

    try {
      await _pdfService.printWorkshopOrder(context, dummyOrder);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _orderIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle), elevation: 0),
      body: ListView(
        children: [
          _buildSectionHeader(l10n.shopInformation),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              controller: _shopNameController,
              decoration: InputDecoration(
                labelText: l10n.shopNameLabel,
                prefixIcon: IconText(Icons.store),
                border: OutlineInputBorder(),
              ),
              inputFormatters: [
                TextInputFormatter.withFunction(
                  (oldValue, newValue) =>
                      newValue.copyWith(text: newValue.text.toUpperCase()),
                ),
              ],
              onChanged: (value) => _settingsService.setShopName(value),
            ),
          ),

          ListTile(
            leading: const IconText(Icons.attach_money),
            title: Text(l10n.currencyLabel),
            subtitle: Text('${l10n.currentPrefix} $_currency'),
            trailing: DropdownButton<String>(
              value: _currency,
              underline: Container(),
              items: ['USD', 'HKD', 'TWD', 'EUR', 'GBP'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (newValue) {
                if (newValue != null) {
                  setState(() => _currency = newValue);
                  _settingsService.setCurrency(newValue);
                }
              },
            ),
          ),

          _buildDivider(),
          _buildSectionHeader(l10n.systemConfiguration),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _orderIdController,
                    decoration: InputDecoration(
                      labelText: l10n.nextOrderNumber,
                      prefixIcon: const IconText(Icons.confirmation_number),
                      border: const OutlineInputBorder(),
                      helperText: l10n.helperSetStartingId,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _updateOrderNumber,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 24,
                    ),
                  ),
                  child: Text(l10n.updateButton),
                ),
              ],
            ),
          ),

          // === 這裡插入了新的管理區塊 ===
          _buildDivider(),
          _buildSectionHeader(l10n.productsServices),

          ListTile(
            leading: const IconText(Icons.category_outlined),
            title: Text(l10n.manageServiceItems),
            subtitle: Text(l10n.manageServiceItemsSub),
            trailing: const IconText(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey,
            ),
            onTap: () => _showServicesManager(context), // 點擊開啟管理視窗
          ),

          ListTile(
            leading: const IconText(Icons.accessibility_new),
            title: Text(l10n.measurementFieldsLabel),
            subtitle: Text(l10n.measurementFieldsSub),
            trailing: const IconText(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey,
            ),
            onTap: () => _showMeasurementFieldsManager(context),
          ),

          _buildDivider(),
          _buildSectionHeader(l10n.printerHardware),

          ListTile(
            leading: const IconText(Icons.print_outlined),
            title: Text(l10n.testPrint),
            subtitle: Text(l10n.testPrintSub),
            trailing: const IconText(Icons.chevron_right),
            onTap: _handleTestPrint,
          ),

          _buildDivider(),
          _buildSectionHeader(l10n.preferencesLabel),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Card(
              elevation: 0,
              color: const Color(0xFF1E1E2C),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.appearance,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const IconText(
                        Icons.color_lens_outlined,
                        color: Colors.grey,
                      ),
                      title: Text(
                        'Theme Accent Color',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        'Choose your preferred highlight color',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: _accentOptions
                          .map(
                            (color) => _buildColorOption(
                              color,
                              isSelected:
                                  _accentColor.toARGB32() == color.toARGB32(),
                              onTap: () => _updateAccentColor(color),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const IconText(
                        Icons.text_fields,
                        color: Colors.grey,
                      ),
                      title: Text(
                        'System Text Color',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        'Change text color used across the app theme',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: _textColorOptions
                          .map(
                            (color) => _buildColorOption(
                              color,
                              isSelected:
                                  _textColor.toARGB32() == color.toARGB32(),
                              onTap: () => _updateTextColor(color),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const IconText(Icons.title, color: Colors.grey),
                      title: Text(
                        'Heading Text Color',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        'Color for page titles and headings',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: _textColorOptions
                          .map(
                            (color) => _buildColorOption(
                              color,
                              isSelected:
                                  _headingTextColor.toARGB32() ==
                                  color.toARGB32(),
                              onTap: () => _updateHeadingTextColor(color),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const IconText(
                        Icons.label_outline,
                        color: Colors.grey,
                      ),
                      title: Text(
                        'Card & Label Color',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        'Color for card titles and form labels',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: _textColorOptions
                          .map(
                            (color) => _buildColorOption(
                              color,
                              isSelected:
                                  _cardTitleColor.toARGB32() ==
                                  color.toARGB32(),
                              onTap: () => _updateCardTitleColor(color),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const IconText(Icons.menu, color: Colors.grey),
                      title: Text(
                        'Sidebar Text Color',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        'Color for navigation sidebar labels and icons',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: _textColorOptions
                          .map(
                            (color) => _buildColorOption(
                              color,
                              isSelected:
                                  _sidebarTextColor.toARGB32() ==
                                  color.toARGB32(),
                              onTap: () => _updateSidebarTextColor(color),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          ListTile(
            leading: const IconText(Icons.language),
            title: Text(l10n.languageLabel),
            subtitle: Text(l10n.systemLanguage),
            trailing: DropdownButton<String>(
              value: _language,
              underline: Container(),
              items: _languages.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (newValue) {
                if (newValue != null) {
                  setState(() => _language = newValue);
                  _settingsService.setLanguage(newValue);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${AppLocalizations.of(context).languageSwitchedTo} $newValue',
                      ),
                    ),
                  );
                }
              },
            ),
          ),

          ListTile(
            leading: const IconText(Icons.straighten),
            title: Text(l10n.fabricUnit),
            subtitle: Text(l10n.defaultUnit),
            trailing: DropdownButton<String>(
              value: _unit,
              underline: Container(),
              items: ['Meters', 'Yards', 'Feet'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (newValue) {
                if (newValue != null) {
                  setState(() => _unit = newValue);
                  _settingsService.setUnit(newValue);
                }
              },
            ),
          ),

          _buildDivider(),
          _buildSectionHeader(l10n.appNotifications),

          SwitchListTile(
            secondary: const IconText(Icons.notifications_active_outlined),
            title: Text(l10n.orderNotificationsLabel),
            subtitle: Text(l10n.alertDueDate),
            value: _enableNotifications,
            onChanged: (val) {
              setState(() => _enableNotifications = val);
              _settingsService.setNotifications(val);
            },
          ),

          _buildDivider(),
          _buildSectionHeader(l10n.systemInfo),

          ListTile(
            leading: const IconText(Icons.info_outline),
            title: Text(l10n.versionLabel),
            subtitle: Text(l10n.versionValue),
          ),
          ListTile(
            leading: const IconText(Icons.delete_forever, color: Colors.red),
            title: Text(
              l10n.resetLocalSettings,
              style: const TextStyle(color: Colors.red),
            ),
            onTap: () async {
              await _settingsService.clearAll();
              await _loadPreferences();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('All local settings reset to default'),
                  ),
                );
              }
            },
          ),

          _buildDivider(),
          _buildSectionHeader(l10n.accountLabel),

          ListTile(
            leading: const IconText(Icons.logout, color: Colors.red),
            title: Text(l10n.logout, style: const TextStyle(color: Colors.red)),
            onTap: () async {
              // 執行登出
              await FirebaseAuth.instance.signOut();
              // AuthWrapper 會自動偵測到登出，並將畫面切換回 LoginPage
            },
          ),

          _buildDivider(),
          _buildSectionHeader(l10n.dataMaintenance),

          ListTile(
            leading: const IconText(
              Icons.cleaning_services,
              color: Colors.orange,
            ),
            title: Text(l10n.cleanOrphanedData),
            subtitle: Text(l10n.cleanOrphanedDataSub),
            trailing: const IconText(Icons.chevron_right),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('確認清除孤立資料'),
                  content: const Text(
                    '系統將掃描並刪除：\n'
                    '• 無對應訂單的訂單明細 (order_items)\n'
                    '• 無對應訂單的工坊工單 (workshop_orders)\n\n'
                    '此操作不可復原，確定繼續？',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('確認清除'),
                    ),
                  ],
                ),
              );

              if (confirmed != true || !mounted) return;

              // Show loading
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('正在掃描資料庫...'),
                  duration: Duration(seconds: 30),
                ),
              );

              try {
                final result = await DatabaseService().cleanupOrphanedData();
                if (!mounted) return;
                messenger.clearSnackBars();
                final orderItemsDeleted = result['orderItems'] ?? 0;
                final workshopDeleted = result['workshopOrders'] ?? 0;
                final total = orderItemsDeleted + workshopDeleted;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      total == 0
                          ? '✅ 資料庫乾淨，無孤立資料'
                          : '✅ 清除完成：刪除 $orderItemsDeleted 筆訂單明細、$workshopDeleted 筆工單',
                    ),
                    backgroundColor: total == 0 ? Colors.green : Colors.orange,
                    duration: const Duration(seconds: 4),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                messenger.clearSnackBars();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('清除失敗：$e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),

          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveAllSettings,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Changes'),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).primaryColor,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildColorOption(
    Color color, {
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final borderColor = color == Colors.white
        ? Colors.grey.shade700
        : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.white : borderColor,
            width: 3,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 8,
                spreadRadius: 2,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() => const Divider(height: 32, thickness: 1);
}
