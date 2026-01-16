import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/customer.dart';
import '../models/order.dart';
import '../services/database_service.dart';

class CustomerDetailsPage extends StatefulWidget {
  final Customer customer;

  const CustomerDetailsPage({super.key, required this.customer});

  @override
  State<CustomerDetailsPage> createState() => _CustomerDetailsPageState();
}

class _CustomerDetailsPageState extends State<CustomerDetailsPage> {
  final DatabaseService _dbService = DatabaseService();
  late Customer _customer;
  
  // 新增：日期篩選相關狀態
  String _revenueFilterMode = 'Month';
  DateTimeRange? _customDateRange;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
  }

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch action'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // === 新增：編輯客戶基本資料 (姓名、電話、Email) ===
  void _showEditProfileDialog() {
    final nameController = TextEditingController(text: _customer.name);
    final phoneController = TextEditingController(text: _customer.phone);
    final emailController = TextEditingController(text: _customer.email);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Customer Profile'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (v) => v!.isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: emailController,
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
                  // 1. 建立更新後的物件
                  final updatedCustomer = _customer.copyWith(
                    name: nameController.text.trim(),
                    phone: phoneController.text.trim(),
                    email: emailController.text.trim(),
                  );
                  
                  // 2. 寫入資料庫
                  await _dbService.updateCustomer(updatedCustomer);
                  
                  // 3. 更新畫面
                  if (mounted) {
                    setState(() {
                      _customer = updatedCustomer;
                    });
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Profile updated successfully'), 
                        backgroundColor: Colors.green
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // 編輯尺寸對話框
  void _showMeasurementsDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );

    try {
      List<String> fields = await _dbService.getMeasurementFieldsStream().first;
      if (fields.isEmpty) {
        await _dbService.seedMeasurementFields();
        fields = await _dbService.getMeasurementFieldsStream().first;
      }

      if (!mounted) return;
      Navigator.pop(context);

      final Map<String, TextEditingController> controllers = {};
      for (var field in fields) {
        controllers[field] = TextEditingController(text: _customer.measurements[field] ?? '');
      }

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Edit Measurements'),
          content: SingleChildScrollView(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: fields.map((field) {
                return SizedBox(
                  width: 120,
                  child: TextFormField(
                    controller: controllers[field],
                    decoration: InputDecoration(
                      labelText: field,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                Map<String, String> newMeasurements = {};
                controllers.forEach((key, controller) {
                  if (controller.text.trim().isNotEmpty) {
                    newMeasurements[key] = controller.text.trim();
                  }
                });

                try {
                  final updatedCustomer = _customer.copyWith(measurements: newMeasurements);
                  await _dbService.updateCustomer(updatedCustomer);
                  
                  if (mounted) {
                    setState(() {
                      _customer = updatedCustomer;
                    });
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Measurements updated!'), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  print(e);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  // 新增：取得當前篩選器的日期範圍 (供多個卡片共用)
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
          // 若未選日期，預設顯示今天
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
        title: const Text('Customer Profile'),
        elevation: 0,
        actions: [
          // 這是頁面右上角的編輯按鈕，現在綁定到修改資料功能
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Profile (Phone/Email)',
            onPressed: _showEditProfileDialog, 
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileHeader(),
            const SizedBox(height: 24),
            
            // Body Measurements Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Body Measurements', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: _showMeasurementsDialog,
                  icon: const Icon(Icons.straighten),
                  label: const Text('Edit'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildMeasurementsGrid(),
            
            const SizedBox(height: 24),
            
            // Order History Section
            const Text('Order History', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildOrderHistoryList(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                  child: Text(
                    _customer.name.isNotEmpty ? _customer.name[0].toUpperCase() : '?',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_customer.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      if (_customer.phone.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.phone, size: 16, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(_customer.phone, style: const TextStyle(fontSize: 16, color: Colors.grey)),
                            ],
                          ),
                        ),
                      if (_customer.email.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(_customer.email, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                        ),
                    ],
                  ),
                ),
                if (_customer.phone.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.call, color: Colors.green),
                    onPressed: () => _launchUrl('tel:${_customer.phone}'),
                  ),
              ],
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Total Spent', '\$${_customer.totalSpent.toStringAsFixed(0)}', Colors.green),
                _buildStatItem('Orders', '${_customer.orders}', Colors.blue),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildMeasurementsGrid() {
    if (_customer.measurements.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: const Center(child: Text('No measurements yet.', style: TextStyle(color: Colors.grey))),
      );
    }

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      childAspectRatio: 2.0,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: _customer.measurements.entries.map((entry) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(entry.key, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              Text(entry.value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildOrderHistoryList() {
    return FutureBuilder<List<Order>>(
      future: _dbService.getOrdersByCustomerId(_customer.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return const Text('Error loading orders');
        
        final orders = snapshot.data ?? [];
        if (orders.isEmpty) return const Text('No orders found.');

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final order = orders[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.receipt_long, color: Colors.blue),
                ),
                title: Text(
                  'Order #${order.id}', 
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  DateFormat('yyyy-MM-dd').format(order.createdAt!),
                  style: TextStyle(color: Colors.grey[600]),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('\$${order.total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    _buildStatusBadge(order.status),
                  ],
                ),
                children: [
                  const Divider(),
                  FutureBuilder<List<OrderItem>>(
                    future: _dbService.getOrderItems(order.id),
                    builder: (context, itemSnapshot) {
                      if (itemSnapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      
                      final items = (itemSnapshot.data != null && itemSnapshot.data!.isNotEmpty)
                          ? itemSnapshot.data!
                          : order.items;

                      if (items.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('No items details found'),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          children: items.map((item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.service} ${item.fabricName != null ? "(${item.fabricName})" : ""}',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                                Text('x${item.quantity}', style: const TextStyle(color: Colors.grey)),
                                const SizedBox(width: 16),
                                Text('\$${item.price.toStringAsFixed(0)}'),
                              ],
                            ),
                          )).toList(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = Colors.grey;
    if (status == 'completed') color = Colors.green;
    if (status == 'pending') color = Colors.orange;
    if (status == 'confirmed') color = Colors.blue;

    return Text(
      status.toUpperCase(),
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
    );
  }
}