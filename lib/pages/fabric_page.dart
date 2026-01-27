import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/material_item.dart';
import '../services/database_service.dart';

class FabricPage extends StatefulWidget {
  const FabricPage({super.key});

  @override
  State<FabricPage> createState() => _FabricPageState();
}

class _FabricPageState extends State<FabricPage> with SingleTickerProviderStateMixin {
  final DatabaseService _dbService = DatabaseService();
  
  final List<String> _categories = ['All', 'Cotton', 'Linen', 'Wool', 'Other'];
  
  late TabController _tabController;
  bool _isUploading = false;

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

  Future<String?> _uploadImage(Uint8List fileData) async {
    try {
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final Reference storageRef = FirebaseStorage.instance.ref().child('fabric_images').child(fileName);
      final SettableMetadata metadata = SettableMetadata(contentType: 'image/jpeg');
      final UploadTask uploadTask = storageRef.putData(fileData, metadata);
      final TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    }
  }

  // === 新增/編輯 對話框 (穩健版：防卡死 + 錯誤提示) ===
  void _showAddEditDialog({MaterialItem? item}) {
    final nameController = TextEditingController(text: item?.name ?? '');
    final costController = TextEditingController(text: item?.costPerUnit.toString() ?? '');
    final stockController = TextEditingController(text: item?.stock.toString() ?? '');
    final reorderController = TextEditingController(text: item?.reorderLevel.toString() ?? '10');
    final unitController = TextEditingController(text: item?.unit ?? 'm');
    
    final retailPriceController = TextEditingController(text: item?.retailPrice.toString() ?? '');
    bool isOnline = item?.isOnline ?? false;

    String selectedCategory = item?.category ?? 'Cotton';
    if (selectedCategory == 'All' || !_categories.contains(selectedCategory)) {
      selectedCategory = 'Other';
    }

    Uint8List? pickedImageBytes;
    String? currentImageUrl = item?.imageUrl;
    
    // 背景上傳任務
    Future<String?>? backgroundUploadTask; 

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(item == null ? 'Add Fabric' : 'Edit Fabric'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 圖片選取區
                  Center(
                    child: GestureDetector(
                      onTap: () async {
                        final ImagePicker picker = ImagePicker();
                        final XFile? image = await picker.pickImage(
                          source: ImageSource.gallery,
                          maxWidth: 1024, // 適度壓縮：限制寬度 1024px，避免檔案過大卡死
                          imageQuality: 85,
                        );
                        
                        if (image != null) {
                          final bytes = await image.readAsBytes();
                          
                          // 開始背景上傳
                          backgroundUploadTask = _uploadImage(bytes);
                          
                          setDialogState(() {
                            pickedImageBytes = bytes;
                          });
                        }
                      },
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[400]!),
                          image: pickedImageBytes != null
                              ? DecorationImage(image: MemoryImage(pickedImageBytes!), fit: BoxFit.cover)
                              : (currentImageUrl != null && currentImageUrl!.isNotEmpty
                                  ? DecorationImage(image: NetworkImage(currentImageUrl!), fit: BoxFit.cover)
                                  : null),
                        ),
                        child: (pickedImageBytes == null && (currentImageUrl == null || currentImageUrl!.isEmpty))
                            ? const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_a_photo, color: Colors.grey),
                                  SizedBox(height: 4),
                                  Text('Add Photo', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                ],
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  SwitchListTile(
                    title: const Text('Available Online'),
                    subtitle: Text(isOnline ? 'Visible to customers' : 'Hidden from store'),
                    value: isOnline,
                    activeColor: Colors.green,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setDialogState(() => isOnline = val),
                  ),
                  const Divider(),

                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: _categories
                        .where((c) => c != 'All')
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
                  
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: costController,
                          decoration: const InputDecoration(labelText: 'Cost Price'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: retailPriceController,
                          decoration: const InputDecoration(
                            labelText: 'Retail Price', 
                            suffixText: '\$',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
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
                          decoration: const InputDecoration(labelText: 'Unit'),
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
                  
                  // 顯示載入中狀態
                  if (_isUploading)
                    const Padding(
                      padding: EdgeInsets.only(top: 16.0),
                      child: Column(
                        children: [
                          LinearProgressIndicator(),
                          SizedBox(height: 4),
                          Text("Saving data...", style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: _isUploading ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                // 只有在非上傳狀態才允許點擊
                onPressed: _isUploading ? null : () async {
                  setDialogState(() => _isUploading = true);

                  try {
                    String? finalImageUrl = currentImageUrl;
                    
                    // 等待背景上傳完成
                    if (backgroundUploadTask != null) {
                      // 設定 20 秒超時，避免無限等待
                      finalImageUrl = await backgroundUploadTask!.timeout(
                        const Duration(seconds: 20),
                        onTimeout: () => null,
                      );
                      
                      // 如果有選圖但網址是 null，代表上傳失敗
                      if (finalImageUrl == null) {
                        throw Exception('Image upload failed or timed out. Please try again.');
                      }
                    }

                    final newItem = MaterialItem(
                      id: item?.id ?? '',
                      name: nameController.text,
                      costPerUnit: double.tryParse(costController.text) ?? 0,
                      stock: double.tryParse(stockController.text) ?? 0,
                      reorderLevel: double.tryParse(reorderController.text) ?? 0,
                      unit: unitController.text,
                      imageUrl: finalImageUrl,
                      category: selectedCategory,
                      retailPrice: double.tryParse(retailPriceController.text) ?? 0,
                      isOnline: isOnline,
                    );

                    if (item == null) {
                      await _dbService.addMaterial(newItem);
                    } else {
                      await _dbService.updateMaterial(newItem);
                    }
                    
                    if (mounted) Navigator.pop(context);
                  } catch (e) {
                    print('Error saving material: $e');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
                      );
                    }
                  } finally {
                    // 無論成功或失敗，都恢復按鈕狀態，避免卡死
                    if (mounted) {
                      setDialogState(() => _isUploading = false);
                    }
                  }
                },
                child: Text(_isUploading ? 'Saving...' : 'Save'),
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

          return TabBarView(
            controller: _tabController,
            children: _categories.map((category) {
              final filteredFabrics = category == 'All'
                  ? allFabrics
                  : allFabrics.where((f) => f.category == category).toList();

              if (filteredFabrics.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text('No $category fabrics found', style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: filteredFabrics.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final fabric = filteredFabrics[index];
                  final isLowStock = fabric.stock <= fabric.reorderLevel;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    leading: GestureDetector(
                      onTap: () {
                        if (fabric.imageUrl != null && fabric.imageUrl!.isNotEmpty) {
                          showDialog(
                            context: context,
                            builder: (_) => Dialog(child: Image.network(fabric.imageUrl!)),
                          );
                        }
                      },
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                          image: (fabric.imageUrl != null && fabric.imageUrl!.isNotEmpty)
                              ? DecorationImage(image: NetworkImage(fabric.imageUrl!), fit: BoxFit.cover)
                              : null,
                        ),
                        child: (fabric.imageUrl == null || fabric.imageUrl!.isEmpty)
                            ? const Icon(Icons.texture, color: Colors.grey)
                            : null,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(child: Text(fabric.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                        // 顯示上架狀態圖示
                        if (fabric.isOnline)
                          const Tooltip(
                            message: 'Online',
                            child: Icon(Icons.public, size: 16, color: Colors.green),
                          )
                        else
                          const Tooltip(
                            message: 'Offline',
                            child: Icon(Icons.public_off, size: 16, color: Colors.grey),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        // 顯示成本與零售價
                        Row(
                          children: [
                            Text(
                              'Cost: \$${fabric.costPerUnit.toStringAsFixed(0)}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Retail: \$${fabric.retailPrice.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(fabric.category, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary)),
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
                                fontSize: 16,
                                color: isLowStock ? Colors.red : Colors.green,
                              ),
                            ),
                            if (isLowStock)
                              const Text('Low Stock', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(width: 16),
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
                                content: Text('Delete ${fabric.name}?'),
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