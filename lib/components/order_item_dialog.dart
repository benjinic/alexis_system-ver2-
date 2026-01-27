import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// Models
import '../models/order.dart';
import '../models/service_item.dart';
import '../models/material_item.dart';

// Services & Providers
import '../services/database_service.dart';
import '../providers/cart_provider.dart';

class OrderItemDialog extends StatefulWidget {
  final OrderItem? existingItem;
  final int? index;

  const OrderItemDialog({
    super.key,
    this.existingItem,
    this.index,
  });

  @override
  State<OrderItemDialog> createState() => _OrderItemDialogState();
}

class _OrderItemDialogState extends State<OrderItemDialog> {
  final DatabaseService _dbService = DatabaseService();

  // Controllers
  late TextEditingController _priceController;
  late TextEditingController _usageController;
  late TextEditingController _quantityController;
  final TextEditingController _suggestedPriceController = TextEditingController();
  final TextEditingController _fabricSearchController = TextEditingController();

  // State
  List<MaterialItem> _fabrics = [];
  bool _isLoadingFabrics = true;
  ServiceItem? _selectedService;
  MaterialItem? _selectedFabric;
  // Fabric categories and current selection
  final List<String> _fabricCategories = ['Cotton', 'Linen', 'Wool', 'Other'];
  String _selectedCategory = 'Cotton';

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _loadData();
  }

  void _initializeControllers() {
    _priceController = TextEditingController(
        text: widget.existingItem?.price.toStringAsFixed(0) ?? '');
    _usageController = TextEditingController(
        text: widget.existingItem?.fabricUsed.toString() ?? '0');
    _quantityController = TextEditingController(
        text: widget.existingItem?.quantity.toString() ?? '1');
  }

  Future<void> _loadData() async {
    try {
      // 讀取布料庫存
      final fabrics = await _dbService.getInventory();
      
      if (mounted) {
        setState(() {
          _fabrics = fabrics;
          _isLoadingFabrics = false;
        });

        // 如果是編輯模式，嘗試還原已選布料
        if (widget.existingItem != null && widget.existingItem!.fabricId != null) {
          try {
            _selectedFabric = _fabrics.firstWhere((f) => f.id == widget.existingItem!.fabricId);
            _calculateValues();
            // Set category based on existing fabric
            if (_selectedFabric != null) {
              _selectedCategory = _fabricCategories.contains(_selectedFabric!.category)
                  ? _selectedFabric!.category
                  : 'Other';
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingFabrics = false);
      }
      print('Error loading fabrics: $e');
    }
  }

  @override
  void dispose() {
    _priceController.dispose();
    _usageController.dispose();
    _quantityController.dispose();
    _suggestedPriceController.dispose();
    _fabricSearchController.dispose();
    super.dispose();
  }

  // === 核心計算邏輯 ===
  void _calculateValues() {
    if (_selectedService != null) {
      double servicePrice = _selectedService!.price;
      double fabricUnitCost = _selectedFabric?.costPerUnit ?? 0.0;
      double currentUsage = double.tryParse(_usageController.text) ?? 0.0;

      double totalFabricCost = fabricUnitCost * currentUsage;
      
      // 公式：(服務費 + 布料總成本) * 2.5
      double suggestedPrice = (servicePrice + totalFabricCost) * 2.5;

      _suggestedPriceController.text = suggestedPrice.toStringAsFixed(0);

      // 如果是新增模式且價格欄位為空，才自動填入
      if (_priceController.text.isEmpty) {
        _priceController.text = suggestedPrice.toStringAsFixed(0);
      }
    }
  }

  void _handleSave() {
    if (_selectedService == null) return;

    final double finalPrice = double.tryParse(_priceController.text) ?? _selectedService!.price;
    final double finalUsage = double.tryParse(_usageController.text) ?? 0.0;
    final int finalQty = int.tryParse(_quantityController.text) ?? 1;
    
    // 計算預估成本 (僅布料)
    double estimatedMaterialCost = 0;
    if (_selectedService != null && _selectedFabric != null) {
      estimatedMaterialCost = finalUsage * _selectedFabric!.costPerUnit;
    }

    final newItem = OrderItem(
      id: widget.existingItem?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      service: _selectedService!.name,
      price: finalPrice,
      quantity: finalQty,
      fabricId: _selectedFabric?.id,
      fabricName: _selectedFabric?.name,
      fabricUsed: finalUsage,
      cost: estimatedMaterialCost,
    );

    // 透過 Provider 更新
    if (widget.existingItem != null && widget.index != null) {
      context.read<CartProvider>().updateItem(widget.index!, newItem);
    } else {
      context.read<CartProvider>().addItem(newItem);
    }
    
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // 預估成本計算 (顯示用)
    double currentUsage = double.tryParse(_usageController.text) ?? 0.0;
    double estimatedMaterialCost = 0;
    if (_selectedService != null && _selectedFabric != null) {
      estimatedMaterialCost = currentUsage * _selectedFabric!.costPerUnit;
    }

    // 布料搜尋過濾
    final fabricSearchQuery = _fabricSearchController.text.toLowerCase();
    final filteredFabrics = _fabrics.where((f) {
      final bool matchCategory = f.category == _selectedCategory;
      final bool matchSearch = f.name.toLowerCase().contains(fabricSearchQuery) ||
          f.id.toLowerCase().contains(fabricSearchQuery);
      return matchCategory && matchSearch;
    }).toList();

    return AlertDialog(
      title: Text(widget.existingItem != null ? 'Edit Item' : 'Add Item'),
      content: _isLoadingFabrics 
          ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // === 1. Service List (no search) ===
                  StreamBuilder<List<ServiceItem>>(
                    stream: _dbService.getServicesStream(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()));
                      }
                      
                      final allServices = snapshot.data ?? [];

                      // 自動還原編輯項目 (僅執行一次)
                      if (widget.existingItem != null && _selectedService == null && allServices.isNotEmpty) {
                         try {
                           final foundService = allServices.firstWhere((s) => s.name == widget.existingItem!.service);
                           // 這裡使用 Future.microtask 避免在 build 期間 setState
                           Future.microtask(() {
                             if (mounted && _selectedService == null) {
                               setState(() {
                                 _selectedService = foundService;
                               });
                               _calculateValues();
                             }
                           });
                         } catch (_) {}
                      }

                      if (allServices.isEmpty) return const Text('No services found.');

                      return ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200), 
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 8.0,
                            runSpacing: 8.0,
                            children: allServices.map((service) {
                              final isSelected = _selectedService?.id == service.id;
                              return ChoiceChip(
                                label: Text('${service.name}'),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() {
                                    _selectedService = selected ? service : null;
                                    if (selected) {
                                      if (_usageController.text == '0') _usageController.text = service.defaultFabricUsage.toString();
                                      if (service.defaultFabricUsage == 0) _selectedFabric = null;
                                      if (widget.existingItem == null) _priceController.clear();
                                      _calculateValues();
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  
                  // === 2. Fabric Selection (category + search) ===
                  if (_selectedService != null && (_selectedService!.defaultFabricUsage > 0 || (widget.existingItem?.fabricUsed ?? 0) > 0)) ...[
                    const Text('2. Select Fabric Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8.0,
                      children: _fabricCategories.map((category) {
                        return ChoiceChip(
                          label: Text(category),
                          selected: _selectedCategory == category,
                          selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedCategory = category;
                                _calculateValues();
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    
                    // Search within selected category
                    TextField(
                      controller: _fabricSearchController,
                      decoration: InputDecoration(
                        hintText: 'Filter $_selectedCategory fabrics...',
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[100],
                      ),
                      onChanged: (value) => setState(() {}),
                    ),
                    const SizedBox(height: 8),

                    if (filteredFabrics.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text('No $_selectedCategory fabric found', style: const TextStyle(color: Colors.grey)),
                      )
                    else
                      Container(
                        height: 150,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.withOpacity(0.3)), 
                          borderRadius: BorderRadius.circular(8)
                        ),
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: filteredFabrics.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final fabric = filteredFabrics[index];
                            final isSelected = _selectedFabric?.id == fabric.id;
                            return ListTile(
                              dense: true,
                              selected: isSelected,
                              selectedTileColor: Theme.of(context).primaryColor.withOpacity(0.1),
                              leading: Container(
                                width: 30, height: 30,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: (fabric.imageUrl?.isNotEmpty ?? false)
                                    ? Image.network(fabric.imageUrl!, fit: BoxFit.cover)
                                    : const Icon(Icons.texture, size: 16),
                              ),
                              title: Text(fabric.name, overflow: TextOverflow.ellipsis),
                              subtitle: Text('\$${fabric.costPerUnit.toStringAsFixed(0)} / ${fabric.unit}'),
                              trailing: isSelected ? Icon(Icons.check_circle, size: 18, color: Theme.of(context).primaryColor) : null,
                              onTap: () => setState(() {
                                _selectedFabric = fabric;
                                _calculateValues();
                              }),
                            );
                          },
                        ),
                      ),
                    
                    const SizedBox(height: 16),
                    
                    // Usage & Cost
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _usageController,
                            decoration: const InputDecoration(labelText: 'Usage (m)', border: OutlineInputBorder()),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) {
                              setState(() {});
                              _calculateValues();
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Est. Cost', style: TextStyle(fontSize: 10, color: Colors.grey)),
                            Text(
                              '\$${estimatedMaterialCost.toStringAsFixed(0)}', 
                              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],

                  // === 4. Price & Quantity ===
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _priceController,
                          decoration: const InputDecoration(labelText: 'Unit Price', prefixIcon: Icon(Icons.attach_money), border: OutlineInputBorder()),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: TextFormField(
                          controller: _quantityController,
                          decoration: const InputDecoration(labelText: 'Qty', prefixIcon: Icon(Icons.numbers), border: OutlineInputBorder()),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                    ],
                  ),

                  // === 5. Suggested Price ===
                  const SizedBox(height: 16),
                  TextField(
                    controller: _suggestedPriceController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Suggested Price',
                      helperText: '(Service + Material) x 2.5',
                      prefixIcon: const Icon(Icons.calculate_outlined, color: Colors.blue),
                      fillColor: Colors.blue.withOpacity(0.05),
                      filled: true,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
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
          onPressed: _selectedService == null ? null : _handleSave,
          child: Text(widget.existingItem != null ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}