import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/settings_service.dart';
import '../services/database_service.dart';
import '../services/pdf_service.dart';
import '../models/service_item.dart';
import '../models/workshop_order.dart';
import '../models/workshop_status.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsService _settingsService = SettingsService();
  final DatabaseService _dbService = DatabaseService();
  final PdfService _pdfService = PdfService();

  // 預設值
  String _currency = 'USD';
  String _language = 'English';
  String _unit = 'Meters';
  bool _enableNotifications = true;

  final TextEditingController _shopNameController = TextEditingController();
  final TextEditingController _orderIdController = TextEditingController();

  bool _isLoading = true;
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
      _isLoading = false;
    });
  }

  // 讀取雲端訂單號碼
  void _loadCurrentOrderNumber() {
    _dbService.getNextOrderIdStream().first.then((nextId) {
      if (mounted) {
        setState(() {
          _orderIdController.text = nextId.toString();
        });
      }
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
                        icon: const Icon(Icons.close),
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
                      if (snapshot.hasError)
                        return Center(child: Text('Error: ${snapshot.error}'));
                      if (snapshot.connectionState == ConnectionState.waiting)
                        return const Center(child: CircularProgressIndicator());

                      final services = snapshot.data ?? [];

                      if (services.isEmpty) {
                        return const Center(
                          child: Text('No services found. Add one!'),
                        );
                      }

                      return ListView.separated(
                        itemCount: services.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) {
                          final item = services[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue[50],
                              child: const Icon(
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
                              'Price: \$${item.price.toStringAsFixed(0)} / ${item.durationDays} days',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
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
                      icon: const Icon(Icons.add),
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
                        icon: const Icon(Icons.close),
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
                        if (snapshot.hasError)
                          return Text('Error: ${snapshot.error}');
                        if (snapshot.connectionState == ConnectionState.waiting)
                          return const Center(
                            child: CircularProgressIndicator(),
                          );

                        final fields = snapshot.data ?? [];

                        return ListView.builder(
                          itemCount: fields.length,
                          itemBuilder: (context, index) {
                            return ListTile(
                              dense: true,
                              title: Text(fields[index]),
                              trailing: IconButton(
                                icon: const Icon(
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

              if (name.isNotEmpty) {
                final newItem = ServiceItem(
                  id: item?.id ?? '',
                  name: name,
                  price: price,
                  defaultFabricUsage: usage,
                  durationDays: days, // Save duration
                );

                if (isEditing) {
                  await _dbService.updateService(newItem);
                } else {
                  await _dbService.addService(newItem);
                }
                if (ctx.mounted) Navigator.pop(ctx);
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

    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), elevation: 0),
      body: ListView(
        children: [
          _buildSectionHeader('Shop Information'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              controller: _shopNameController,
              decoration: const InputDecoration(
                labelText: 'Shop Name',
                prefixIcon: Icon(Icons.store),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => _settingsService.setShopName(value),
            ),
          ),

          ListTile(
            leading: const Icon(Icons.attach_money),
            title: const Text('Currency'),
            subtitle: Text('Current: $_currency'),
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
          _buildSectionHeader('System Configuration'),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _orderIdController,
                    decoration: const InputDecoration(
                      labelText: 'Next Order Number',
                      prefixIcon: Icon(Icons.confirmation_number),
                      border: OutlineInputBorder(),
                      helperText: 'Manually set the starting ID',
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
                  child: const Text('Update'),
                ),
              ],
            ),
          ),

          // === 這裡插入了新的管理區塊 ===
          _buildDivider(),
          _buildSectionHeader('Products & Services'),

          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Manage Service Items'),
            subtitle: const Text('Add, edit prices & fabric usage'),
            trailing: const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey,
            ),
            onTap: () => _showServicesManager(context), // 點擊開啟管理視窗
          ),

          ListTile(
            leading: const Icon(Icons.accessibility_new),
            title: const Text('Measurement Fields'),
            subtitle: const Text('Customize body measurement inputs'),
            trailing: const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey,
            ),
            onTap: () => _showMeasurementFieldsManager(context),
          ),

          _buildDivider(),
          _buildSectionHeader('Printer & Hardware'),

          ListTile(
            leading: const Icon(Icons.print_outlined),
            title: const Text('Test Workshop Ticket Print'),
            subtitle: const Text(
              'Print a sample A4 job ticket to check layout',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _handleTestPrint,
          ),

          _buildDivider(),
          _buildSectionHeader('Preferences'),

          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Language'),
            subtitle: const Text('System language'),
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
                    SnackBar(content: Text('Language switched to $newValue')),
                  );
                }
              },
            ),
          ),

          ListTile(
            leading: const Icon(Icons.straighten),
            title: const Text('Fabric Unit'),
            subtitle: const Text('Default unit for inventory'),
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
          _buildSectionHeader('App Notifications'),

          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Order Notifications'),
            subtitle: const Text('Alert when due date is close'),
            value: _enableNotifications,
            onChanged: (val) {
              setState(() => _enableNotifications = val);
              _settingsService.setNotifications(val);
            },
          ),

          _buildDivider(),
          _buildSectionHeader('System Info'),

          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: const Text('Ver 2.3.0 (Beta)'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text(
              'Reset Local Settings',
              style: TextStyle(color: Colors.red),
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
          _buildSectionHeader('Account'),

          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () async {
              // 執行登出
              await FirebaseAuth.instance.signOut();
              // AuthWrapper 會自動偵測到登出，並將畫面切換回 LoginPage
            },
          ),

          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: ElevatedButton(
              onPressed: () {
                _settingsService.setShopName(_shopNameController.text);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Settings Saved Successfully')),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Save Changes'),
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

  Widget _buildDivider() => const Divider(height: 32, thickness: 1);
}
