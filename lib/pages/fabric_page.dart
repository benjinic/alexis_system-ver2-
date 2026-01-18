import 'package:flutter/material.dart';
import '../models/material_item.dart';
import '../services/database_service.dart';

class FabricPage extends StatefulWidget {
  const FabricPage({super.key});

  @override
  State<FabricPage> createState() => _FabricPageState();
}

class _FabricPageState extends State<FabricPage> with SingleTickerProviderStateMixin {
  final DatabaseService _dbService = DatabaseService();
  
  // 定義分類清單
  final List<String> _categories = ['All', 'Cotton', 'Linen', 'Wool', 'Other'];
  
  // 控制選中的 Tab
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // === 新增/編輯 對話框 ===
  void _showAddEditDialog({MaterialItem? item}) {
    final nameController = TextEditingController(text: item?.name ?? '');
    final costController = TextEditingController(text: item?.costPerUnit.toString() ?? '');
    final stockController = TextEditingController(text: item?.stock.toString() ?? '');
    final reorderController = TextEditingController(text: item?.reorderLevel.toString() ?? '10');
    final unitController = TextEditingController(text: item?.unit ?? 'm');
    final imageController = TextEditingController(text: item?.imageUrl ?? '');
    
    // 分類選擇 (預設為 Cotton 或原本的分類)
    String selectedCategory = item?.category ?? 'Cotton';
    // 確保選取的分類在清單內 (排除 'All')
    if (selectedCategory == 'All' || !_categories.contains(selectedCategory)) {
      selectedCategory = 'Other';
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(item == null ? 'Add Fabric' : 'Edit Fabric'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. 分類選擇
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: _categories
                        .where((c) => c != 'All') // 排除 'All' 選項
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (val) => setDialogState(() => selectedCategory = val!),
                  ),
                  const SizedBox(height: 12),
                  
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: costController,
                    decoration: const InputDecoration(labelText: 'Cost Per Unit'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: stockController,
                          decoration: const InputDecoration(labelText: 'Stock'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: unitController,
                          decoration: const InputDecoration(labelText: 'Unit (e.g. m, yd)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: reorderController,
                    decoration: const InputDecoration(labelText: 'Reorder Level'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: imageController,
                    decoration: const InputDecoration(labelText: 'Image URL (Optional)'),
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
                onPressed: () async {
                  final newItem = MaterialItem(
                    id: item?.id ?? '',
                    name: nameController.text,
                    costPerUnit: double.tryParse(costController.text) ?? 0,
                    stock: double.tryParse(stockController.text) ?? 0,
                    reorderLevel: double.tryParse(reorderController.text) ?? 0,
                    unit: unitController.text,
                    imageUrl: imageController.text.isEmpty ? null : imageController.text,
                    category: selectedCategory, // 儲存分類
                  );

                  if (item == null) {
                    await _dbService.addMaterial(newItem);
                  } else {
                    await _dbService.updateMaterial(newItem);
                  }
                  if (mounted) Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fabric Inventory'),
        // 2. 加入 TabBar
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _categories.map((c) => Tab(text: c)).toList(),
        ),
      ),
      body: StreamBuilder<List<MaterialItem>>(
        stream: _dbService.getInventoryStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final allFabrics = snapshot.data ?? [];

          // 3. 使用 TabBarView 顯示對應內容
          return TabBarView(
            controller: _tabController,
            children: _categories.map((category) {
              // 篩選邏輯
              final filteredFabrics = category == 'All'
                  ? allFabrics
                  : allFabrics.where((f) => f.category == category).toList();

              if (filteredFabrics.isEmpty) {
                return Center(
                  child: Text('No $category fabrics found', style: const TextStyle(color: Colors.grey)),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: filteredFabrics.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final fabric = filteredFabrics[index];
                  // 檢查庫存量是否過低
                  final isLowStock = fabric.stock <= fabric.reorderLevel;

                  return ListTile(
                    leading: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                        image: (fabric.imageUrl != null && fabric.imageUrl!.isNotEmpty)
                            ? DecorationImage(image: NetworkImage(fabric.imageUrl!), fit: BoxFit.cover)
                            : null,
                      ),
                      child: (fabric.imageUrl == null || fabric.imageUrl!.isEmpty)
                          ? const Icon(Icons.texture, color: Colors.grey)
                          : null,
                    ),
                    title: Text(fabric.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Cost: \$${fabric.costPerUnit.toStringAsFixed(0)} / ${fabric.unit}'),
                        // 顯示分類標籤
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(fabric.category, style: const TextStyle(fontSize: 10, color: Colors.blue)),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${fabric.stock.toStringAsFixed(1)} ${fabric.unit}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isLowStock ? Colors.red : Colors.green,
                              ),
                            ),
                            if (isLowStock)
                              const Text('Low Stock', style: TextStyle(fontSize: 10, color: Colors.red)),
                          ],
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _showAddEditDialog(item: fabric),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete Fabric'),
                                content: Text('Are you sure you want to delete ${fabric.name}?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                  ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete')),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await _dbService.deleteMaterial(fabric.id);
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            }).toList(),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}