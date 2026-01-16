import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../services/database_service.dart';
import '../models/material_item.dart';

class FabricPage extends StatefulWidget {
  const FabricPage({super.key});

  @override
  State<FabricPage> createState() => _FabricPageState();
}

class _FabricPageState extends State<FabricPage> {
  final DatabaseService _dbService = DatabaseService();
  bool _isUploading = false;

  // 顯示 新增/編輯 布料的對話框
  void _showFabricDialog(BuildContext context, {MaterialItem? item}) {
    final formKey = GlobalKey<FormState>();
    
    final nameController = TextEditingController(text: item?.name ?? '');
    final categoryController = TextEditingController(text: item?.category ?? 'Fabric');
    final unitController = TextEditingController(text: item?.unit ?? 'meters');
    final costController = TextEditingController(text: item?.costPerUnit.toString() ?? '0');
    final descController = TextEditingController(text: item?.description ?? '');
    
    Uint8List? selectedImageBytes;
    String? currentImageUrl = item?.imageUrl;

    showDialog(
      context: context,
      barrierDismissible: !_isUploading, // 上傳中禁止關閉
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(item == null ? 'Add to Catalog' : 'Edit Fabric'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // === 1. 圖片選取區塊 ===
                      GestureDetector(
                        onTap: () async {
                          final picker = ImagePicker();
                          final XFile? image = await picker.pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 80, // 壓縮圖片品質
                          );
                          
                          if (image != null) {
                            final bytes = await image.readAsBytes();
                            setDialogState(() {
                              selectedImageBytes = bytes;
                            });
                          }
                        },
                        child: Container(
                          height: 180,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[300]!),
                            image: selectedImageBytes != null
                                ? DecorationImage(
                                    image: MemoryImage(selectedImageBytes!),
                                    fit: BoxFit.cover,
                                  )
                                : (currentImageUrl != null && currentImageUrl.isNotEmpty
                                    ? DecorationImage(
                                        image: NetworkImage(currentImageUrl),
                                        fit: BoxFit.cover,
                                      )
                                    : null),
                          ),
                          child: (selectedImageBytes == null && (currentImageUrl == null || currentImageUrl.isEmpty))
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_a_photo, size: 40, color: Colors.grey[500]),
                                    const SizedBox(height: 8),
                                    Text("Tap to add photo", style: TextStyle(color: Colors.grey[600])),
                                  ],
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // === 2. 基本資料欄位 ===
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Fabric Name',
                          prefixIcon: Icon(Icons.label_outline),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v!.isEmpty ? 'Name is required' : null,
                      ),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: categoryController,
                              decoration: const InputDecoration(
                                labelText: 'Category',
                                prefixIcon: Icon(Icons.category_outlined),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: costController,
                              decoration: const InputDecoration(
                                labelText: 'Cost',
                                prefixIcon: Icon(Icons.attach_money),
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (v) => v!.isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      TextFormField(
                        controller: descController,
                        decoration: const InputDecoration(
                          labelText: 'Description (e.g. 100% Wool)',
                          prefixIcon: Icon(Icons.description_outlined),
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                if (!_isUploading)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                
                ElevatedButton(
                  onPressed: _isUploading 
                    ? null 
                    : () async {
                      if (formKey.currentState!.validate()) {
                        setDialogState(() => _isUploading = true); // 開始轉圈

                        try {
                          String? finalImageUrl = currentImageUrl;

                          // === 處理圖片上傳 ===
                          if (selectedImageBytes != null) {
                            final String fileName = DateTime.now().millisecondsSinceEpoch.toString();
                            final ref = FirebaseStorage.instance.ref().child('fabrics/$fileName.jpg');
                            
                            final metadata = SettableMetadata(contentType: 'image/jpeg');
                            await ref.putData(selectedImageBytes!, metadata);
                            
                            finalImageUrl = await ref.getDownloadURL();
                          }

                          // === 建立資料物件 ===
                          final newItem = MaterialItem(
                            id: item?.id ?? '', 
                            name: nameController.text,
                            category: categoryController.text,
                            unit: unitController.text,
                            costPerUnit: double.tryParse(costController.text) ?? 0.0,
                            imageUrl: finalImageUrl,
                            description: descController.text,
                          );

                          // === 寫入 Firestore ===
                          if (item == null) {
                            await _dbService.addMaterial(newItem);
                          } else {
                            await _dbService.updateMaterial(newItem);
                          }

                          if (mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Saved successfully!'), backgroundColor: Colors.green),
                            );
                          }
                        } catch (e) {
                          print('Error uploading: $e');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                            );
                          }
                        } finally {
                          if (mounted) {
                            setDialogState(() => _isUploading = false);
                          }
                        }
                      }
                    },
                  child: _isUploading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                    : Text(item == null ? 'Add' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fabric Catalog'),
        elevation: 0,
      ),
      body: StreamBuilder<List<MaterialItem>>(
        stream: _dbService.getInventoryStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final materials = snapshot.data ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Area
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Fabric Catalog',
                          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${materials.length} items in library',
                          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    FloatingActionButton.extended(
                      onPressed: () => _showFabricDialog(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Add New'),
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Grid View for Catalog style
                if (materials.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40), 
                      child: Text("No fabrics in catalog yet.\nClick 'Add New' to start.", textAlign: TextAlign.center)
                    )
                  )
                else
                  // 使用 GridView 或 ListView，這裡用 ListView + Card 呈現型錄感
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: materials.length,
                    separatorBuilder: (ctx, index) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      return _buildCatalogCard(context, materials[index]);
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCatalogCard(BuildContext context, MaterialItem item) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showFabricDialog(context, item: item), // 點擊整張卡片編輯
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左側圖片區
            SizedBox(
              width: 120,
              height: 120,
              child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                  ? Image.network(
                      item.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => 
                          Container(color: Colors.grey[200], child: const Icon(Icons.broken_image, color: Colors.grey)),
                    )
                  : Container(
                      color: Colors.blue[50],
                      child: Icon(Icons.texture, size: 40, color: Colors.blue[200]),
                    ),
            ),
            
            // 右側資訊區
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.category,
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.description.isNotEmpty ? item.description : 'No description',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '\$${item.costPerUnit.toStringAsFixed(0)} / ${item.unit}',
                          style: TextStyle(
                            fontSize: 16, 
                            fontWeight: FontWeight.bold, 
                            color: Theme.of(context).primaryColor
                          ),
                        ),
                        // 刪除按鈕 (避免誤觸，做成小圖示)
                        InkWell(
                          onTap: () {
                             _showDeleteConfirm(context, item);
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(4.0),
                            child: Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, MaterialItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Fabric'),
        content: Text('Are you sure you want to delete "${item.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              _dbService.deleteMaterial(item.id);
              Navigator.pop(ctx);
            }, 
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
