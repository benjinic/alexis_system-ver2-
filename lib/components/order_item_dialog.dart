import 'package:flutter/material.dart';
import 'icon_text.dart';
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

  /// true = existingItem 只用嚟預填，儲存時當新增項目（標題顯示 Add Item）。
  /// 例如由 Bespoke 匯入時預填服務、布料、用量同價錢。
  final bool asNewItem;

  /// 顯示喺視窗頂部嘅提示文字（例如「匯入自 Bespoke：外套 1/3」）。
  final String? contextNote;

  const OrderItemDialog({
    super.key,
    this.existingItem,
    this.index,
    this.asNewItem = false,
    this.contextNote,
  });

  bool get _isEditing => existingItem != null && !asNewItem;

  @override
  State<OrderItemDialog> createState() => _OrderItemDialogState();
}

class _OrderItemDialogState extends State<OrderItemDialog> {
  final DatabaseService _dbService = DatabaseService();

  // Controllers
  late TextEditingController _priceController;
  late TextEditingController _usageController;
  late TextEditingController _quantityController;
  final TextEditingController _suggestedPriceController =
      TextEditingController();
  final TextEditingController _fabricSearchController = TextEditingController();

  // State
  List<MaterialItem> _fabrics = [];
  bool _isLoadingFabrics = true;
  ServiceItem? _selectedService;
  MaterialItem? _selectedFabric;
  bool _isManualPriceEdited = false;
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
      text: widget.existingItem?.price.toStringAsFixed(0) ?? '',
    );
    _usageController = TextEditingController(
      text: widget.existingItem?.fabricUsed.toString() ?? '0',
    );
    _quantityController = TextEditingController(
      text: widget.existingItem?.quantity.toString() ?? '1',
    );
    _isManualPriceEdited = widget.existingItem?.manualUnitPrice ?? false;
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
        if (widget.existingItem != null &&
            widget.existingItem!.fabricId != null) {
          try {
            _selectedFabric = _fabrics.firstWhere(
              (f) => f.id == widget.existingItem!.fabricId,
            );
            _calculateValues();
            // Set category based on existing fabric
            if (_selectedFabric != null) {
              _selectedCategory =
                  _fabricCategories.contains(_selectedFabric!.category)
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
      debugPrint('Error loading fabrics: $e');
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
    }
  }

  void _handleSave() {
    if (_selectedService == null) return;

    final servicePrice = _selectedService!.price;
    final sanitizedPriceText = _priceController.text.trim().replaceAll(',', '');
    final enteredPrice = double.tryParse(sanitizedPriceText);
    final double finalPrice = (enteredPrice ?? servicePrice) < 0
        ? 0
        : (enteredPrice ?? servicePrice);
    final double finalUsage = double.tryParse(_usageController.text) ?? 0.0;
    final int finalQty = int.tryParse(_quantityController.text) ?? 1;
    final bool manualUnitPrice =
        _isManualPriceEdited || (finalPrice - servicePrice).abs() > 0.001;

    // 計算預估成本 (僅布料)
    double estimatedMaterialCost = 0;
    if (_selectedService != null && _selectedFabric != null) {
      estimatedMaterialCost = finalUsage * _selectedFabric!.costPerUnit;
    }

    final newItem = OrderItem(
      id:
          widget.existingItem?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      service: _selectedService!.name,
      price: finalPrice,
      quantity: finalQty,
      fabricId: _selectedFabric?.id,
      fabricName: _selectedFabric?.name,
      fabricUsed: finalUsage,
      cost: estimatedMaterialCost,
      isFabricOrdered: widget.existingItem?.isFabricOrdered ?? false,
      manualUnitPrice: manualUnitPrice,
      sendToWorkshop: widget.existingItem?.sendToWorkshop ?? true,
    );

    // 透過 Provider 更新
    if (widget.existingItem != null && widget.index != null) {
      context.read<CartProvider>().updateItem(widget.index!, newItem);
    } else {
      context.read<CartProvider>().addItem(newItem);
    }

    Navigator.pop(context);
  }

  String _buildAutoNumberedFabricName(String baseName) {
    final normalizedExisting = _fabrics
        .map((f) => f.name.trim().toLowerCase())
        .toSet();

    if (!normalizedExisting.contains(baseName.toLowerCase())) {
      return baseName;
    }

    var counter = 2;
    while (normalizedExisting.contains('$baseName ($counter)'.toLowerCase())) {
      counter++;
    }
    return '$baseName ($counter)';
  }

  Future<void> _showAddFabricDialog() async {
    final nameCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    final stockCtrl = TextEditingController(text: '0');
    final reorderCtrl = TextEditingController(text: '0');
    final imageUrlCtrl = TextEditingController();
    final unitOptions = ['m', 'yard', 'ft'];
    String selectedUnit = 'm';
    String selectedCategory = _selectedCategory;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Add Fabric'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Fabric Name',
                    border: OutlineInputBorder(),
                  ),
                  inputFormatters: [
                    TextInputFormatter.withFunction(
                      (oldValue, newValue) =>
                          newValue.copyWith(text: newValue.text.toUpperCase()),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: costCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cost Per Unit',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: stockCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Stock',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedUnit,
                        decoration: const InputDecoration(
                          labelText: 'Unit',
                          border: OutlineInputBorder(),
                        ),
                        items: unitOptions
                            .map(
                              (u) => DropdownMenuItem(value: u, child: Text(u)),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() {
                              selectedUnit = value;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reorderCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Reorder Level',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: _fabricCategories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        selectedCategory = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: imageUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Image URL (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final name = nameCtrl.text.trim();
                final cost = double.tryParse(costCtrl.text.trim());
                final stock = double.tryParse(stockCtrl.text.trim()) ?? 0;
                final reorderLevel =
                    double.tryParse(reorderCtrl.text.trim()) ?? 0;

                if (name.isEmpty || cost == null || cost < 0) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Please enter valid fabric name and cost.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final duplicated = _fabrics
                    .where(
                      (f) => f.name.trim().toLowerCase() == name.toLowerCase(),
                    )
                    .toList();

                String finalName = name;
                String? overwriteId;

                if (duplicated.isNotEmpty) {
                  final decision = await showDialog<String>(
                    context: dialogContext,
                    builder: (dupCtx) => AlertDialog(
                      title: const Text('Duplicate Fabric Name'),
                      content: Text(
                        'Fabric "$name" already exists.\n\n'
                        'Choose how to continue:',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dupCtx, 'cancel'),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dupCtx, 'overwrite'),
                          child: const Text('Overwrite Existing'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(dupCtx, 'auto'),
                          child: const Text('Auto-Number New'),
                        ),
                      ],
                    ),
                  );

                  if (decision == null || decision == 'cancel') {
                    return;
                  }
                  if (decision == 'overwrite') {
                    overwriteId = duplicated.first.id;
                    finalName = duplicated.first.name;
                  } else {
                    finalName = _buildAutoNumberedFabricName(name);
                  }
                }

                final newMaterial = MaterialItem(
                  id: overwriteId ?? '',
                  name: finalName,
                  costPerUnit: cost,
                  unit: selectedUnit,
                  stock: stock,
                  reorderLevel: reorderLevel,
                  imageUrl: imageUrlCtrl.text.trim().isEmpty
                      ? null
                      : imageUrlCtrl.text.trim(),
                  category: selectedCategory,
                );

                try {
                  if (overwriteId != null) {
                    await _dbService.updateMaterial(newMaterial);
                  } else {
                    await _dbService.addMaterial(newMaterial);
                  }
                  await _loadData();

                  if (!mounted) return;
                  setState(() {
                    _selectedCategory = selectedCategory;
                    if (overwriteId != null) {
                      final existingIndex = _fabrics.indexWhere(
                        (f) => f.id == overwriteId,
                      );
                      if (existingIndex >= 0) {
                        _selectedFabric = _fabrics[existingIndex];
                        return;
                      }
                    }
                    final matched = _fabrics.where(
                      (f) =>
                          f.name.trim().toLowerCase() ==
                              finalName.toLowerCase() &&
                          (f.costPerUnit - cost).abs() < 0.001 &&
                          f.category == selectedCategory,
                    );
                    if (matched.isNotEmpty) {
                      _selectedFabric = matched.last;
                    }
                  });
                  _calculateValues();

                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        overwriteId != null
                            ? 'Fabric "$finalName" overwritten.'
                            : 'Fabric "$finalName" added.',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Failed to add fabric: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Add Fabric'),
            ),
          ],
        ),
      ),
    );
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
      final bool matchSearch =
          f.name.toLowerCase().contains(fabricSearchQuery) ||
          f.id.toLowerCase().contains(fabricSearchQuery);
      return matchCategory && matchSearch;
    }).toList();

    return AlertDialog(
      title: Text(widget._isEditing ? 'Edit Item' : 'Add Item'),
      content: _isLoadingFabrics
          ? const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.contextNote != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.contextNote!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // === 1. Service List (no search) ===
                  StreamBuilder<List<ServiceItem>>(
                    stream: _dbService.getServicesStream(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      final allServices = snapshot.data ?? [];

                      // 自動還原編輯項目 (僅執行一次)
                      if (widget.existingItem != null &&
                          _selectedService == null &&
                          allServices.isNotEmpty) {
                        try {
                          final foundService = allServices.firstWhere(
                            (s) => s.name == widget.existingItem!.service,
                          );
                          // 這裡使用 Future.microtask 避免在 build 期間 setState
                          Future.microtask(() {
                            if (mounted && _selectedService == null) {
                              setState(() {
                                _selectedService = foundService;
                                if (!_isManualPriceEdited ||
                                    _priceController.text.trim().isEmpty) {
                                  _priceController.text = foundService.price
                                      .toStringAsFixed(0);
                                }
                              });
                              _calculateValues();
                            }
                          });
                        } catch (_) {}
                      }

                      if (allServices.isEmpty) {
                        return const Text('No services found.');
                      }

                      return ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 8.0,
                            runSpacing: 8.0,
                            children: allServices.map((service) {
                              final isSelected =
                                  _selectedService?.id == service.id;
                              return ChoiceChip(
                                label: Text(service.name),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() {
                                    _selectedService = selected
                                        ? service
                                        : null;
                                    if (selected) {
                                      if (_usageController.text == '0') {
                                        _usageController.text = service
                                            .defaultFabricUsage
                                            .toString();
                                      }
                                      if (service.defaultFabricUsage == 0) {
                                        _selectedFabric = null;
                                      }
                                      if (!_isManualPriceEdited ||
                                          _priceController.text
                                              .trim()
                                              .isEmpty) {
                                        _priceController.text = service.price
                                            .toStringAsFixed(0);
                                      }
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
                  if (_selectedService != null) ...[
                    const Text(
                      '2. Select Fabric Type',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _showAddFabricDialog,
                        child: const Text('+ Add Fabric'),
                      ),
                    ),
                    Wrap(
                      spacing: 8.0,
                      children: _fabricCategories.map((category) {
                        return ChoiceChip(
                          label: Text(category),
                          selected: _selectedCategory == category,
                          selectedColor: Theme.of(
                            context,
                          ).primaryColor.withValues(alpha: 0.2),
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
                        prefixIcon: const IconText(Icons.search),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor:
                            Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[800]
                            : Colors.grey[100],
                      ),
                      onChanged: (value) => setState(() {}),
                    ),
                    const SizedBox(height: 8),

                    if (filteredFabrics.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          'No $_selectedCategory fabric found',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      )
                    else
                      Container(
                        height: 150,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.grey.withValues(alpha: 0.3),
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: filteredFabrics.length,
                          separatorBuilder: (_, separatorIndex) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final fabric = filteredFabrics[index];
                            final isSelected = _selectedFabric?.id == fabric.id;
                            return ListTile(
                              dense: true,
                              selected: isSelected,
                              selectedTileColor: Theme.of(
                                context,
                              ).primaryColor.withValues(alpha: 0.1),
                              leading: Container(
                                width: 30,
                                height: 30,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: (fabric.imageUrl?.isNotEmpty ?? false)
                                    ? Image.network(
                                        fabric.imageUrl!,
                                        fit: BoxFit.cover,
                                      )
                                    : const IconText(Icons.texture, size: 16),
                              ),
                              title: Text(
                                fabric.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '\$${fabric.costPerUnit.toStringAsFixed(0)} / ${fabric.unit}',
                              ),
                              trailing: isSelected
                                  ? IconText(
                                      Icons.check_circle,
                                      size: 18,
                                      color: Theme.of(context).primaryColor,
                                    )
                                  : null,
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
                            decoration: const InputDecoration(
                              labelText: 'Usage (m)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
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
                            Text(
                              'Est. Cost',
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.7),
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

                  // === 4. Price & Quantity ===
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _priceController,
                          readOnly: false,
                          decoration: InputDecoration(
                            labelText: 'Unit Price',
                            prefixIcon: const IconText(Icons.attach_money),
                            border: const OutlineInputBorder(),
                            suffixIcon: _selectedService == null
                                ? null
                                : IconButton(
                                    tooltip: 'Reset to service price',
                                    icon: const IconText(Icons.refresh),
                                    onPressed: () {
                                      setState(() {
                                        _isManualPriceEdited = false;
                                        _priceController.text =
                                            _selectedService!.price
                                                .toStringAsFixed(0);
                                      });
                                    },
                                  ),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,2}'),
                            ),
                          ],
                          onChanged: (_) {
                            if (!_isManualPriceEdited) {
                              setState(() {
                                _isManualPriceEdited = true;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: TextFormField(
                          controller: _quantityController,
                          decoration: const InputDecoration(
                            labelText: 'Qty',
                            prefixIcon: IconText(Icons.numbers),
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

                  // === 5. Suggested Price ===
                  const SizedBox(height: 16),
                  TextField(
                    controller: _suggestedPriceController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Suggested Price',
                      helperText: '(Service + Material) x 2.5',
                      prefixIcon: const IconText(
                        Icons.calculate_outlined,
                        color: Colors.blue,
                      ),
                      fillColor: Colors.blue.withValues(alpha: 0.05),
                      filled: true,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    style: const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
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
          child: Text(widget._isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
