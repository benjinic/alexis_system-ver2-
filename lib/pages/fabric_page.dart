import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../components/icon_text.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../l10n/app_localizations.dart';
import '../models/material_item.dart';
import '../services/ai_fabric_scan_service.dart';
import '../services/database_service.dart';

class FabricPage extends StatefulWidget {
  const FabricPage({super.key});

  @override
  State<FabricPage> createState() => _FabricPageState();
}

// ─── Batch scan helpers ───────────────────────────────────────────────────────

/// Groups one scanned image with the fabric results Gemini extracted from it.
class _ScanImageGroup {
  const _ScanImageGroup({required this.imageBytes, required this.results});
  final Uint8List imageBytes;
  final List<AiFabricScanResult> results;
}

class _BatchRow {
  _BatchRow({
    required this.nameCtrl,
    required this.category,
    required this.colorCtrl,
    required this.costCtrl,
    required this.retailCtrl,
    required this.unitCtrl,
    required this.isOnline,
    required this.checked,
    this.sourceImageBytes,
  });

  factory _BatchRow.fromResult(
    AiFabricScanResult r, {
    Uint8List? imageBytes,
  }) {
    const validCats = ['Cotton', 'Linen', 'Wool', 'Other'];
    return _BatchRow(
      nameCtrl: TextEditingController(text: r.name),
      category: validCats.contains(r.category) ? r.category : 'Other',
      colorCtrl: TextEditingController(text: r.color.toUpperCase()),
      costCtrl: TextEditingController(
        text: (r.costPerUnit != null && r.costPerUnit! > 0)
            ? r.costPerUnit!.toStringAsFixed(0)
            : '',
      ),
      retailCtrl: TextEditingController(
        text: (r.retailPrice != null && r.retailPrice! > 0)
            ? r.retailPrice!.toStringAsFixed(0)
            : '',
      ),
      unitCtrl: TextEditingController(text: 'm'),
      isOnline: false,
      checked: r.name.isNotEmpty,
      sourceImageBytes: imageBytes,
    );
  }

  final TextEditingController nameCtrl;
  String category;
  final TextEditingController colorCtrl;
  final TextEditingController costCtrl;
  final TextEditingController retailCtrl;
  final TextEditingController unitCtrl;
  bool isOnline;
  bool checked;
  final Uint8List? sourceImageBytes;
}

class _BatchScanManagerDialog extends StatefulWidget {
  const _BatchScanManagerDialog({
    required this.fabricScanService,
    required this.onComplete,
  });

  final AiFabricScanService fabricScanService;
  final void Function(List<_ScanImageGroup>) onComplete;

  @override
  State<_BatchScanManagerDialog> createState() =>
      _BatchScanManagerDialogState();
}

class _BatchScanManagerDialogState extends State<_BatchScanManagerDialog> {
  final List<_ScanImageGroup> _groups = [];
  final List<_ScanLogEntry> _log = [];
  bool _isScanning = false;
  int _imageCount = 0;

  int get _totalResults =>
      _groups.fold(0, (sum, g) => sum + g.results.length);

  Future<void> _pickAndScan() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage();
    if (images.isEmpty || !mounted) return;

    setState(() => _isScanning = true);

    for (final image in images) {
      if (!mounted) break;

      _imageCount++;
      final idx = _imageCount;
      setState(() {
        _log.add(
          _ScanLogEntry(label: '正在掃描第 $idx 張…', status: _LogStatus.scanning),
        );
      });

      try {
        final bytes = await image.readAsBytes();
        if (!mounted) break;
        final ext = image.name.split('.').last.toLowerCase();
        final mimeType = switch (ext) {
          'png' => 'image/png',
          'gif' => 'image/gif',
          'webp' => 'image/webp',
          'heic' || 'heif' => 'image/heic',
          _ => 'image/jpeg',
        };
        final results = await widget.fabricScanService.scanFabricLabelBatch(
          imageBytes: bytes,
          mimeType: mimeType,
        );
        if (!mounted) break;
        setState(() {
          _groups.add(_ScanImageGroup(imageBytes: bytes, results: results));
          _log.last = _ScanLogEntry(
            label: '第 $idx 張：辨識出 ${results.length} 筆',
            status: _LogStatus.done,
          );
        });
      } catch (e) {
        debugPrint('Batch scan image $idx error: $e');
        if (!mounted) break;
        final errMsg = e.toString().replaceFirst('Exception: ', '');
        setState(() {
          _log.last = _ScanLogEntry(
            label: '第 $idx 張：掃描失敗 — $errMsg',
            status: _LogStatus.error,
          );
        });
      }
    }

    if (mounted) setState(() => _isScanning = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Batch AI Scan', // l10n: batchScan
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '已掃描 $_imageCount 張，共辨識 $_totalResults 筆布料',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
              if (_log.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxHeight: 160),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: _log.length,
                    itemBuilder: (_, i) {
                      final entry = _log[i];
                      final (icon, color) = switch (entry.status) {
                        _LogStatus.scanning => (Icons.hourglass_top, cs.primary),
                        _LogStatus.done => (Icons.check_circle_outline, cs.tertiary),
                        _LogStatus.error => (Icons.error_outline, cs.error),
                      };
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Icon(icon, size: 14, color: color),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                entry.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton(
                    onPressed: _isScanning
                        ? null
                        : () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _isScanning ? null : _pickAndScan,
                    icon: _isScanning
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.primary,
                            ),
                          )
                        : const Icon(Icons.add_photo_alternate_outlined, size: 18),
                    label: Text(_isScanning ? '掃描中…' : '選擇圖片'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (_isScanning || _groups.isEmpty)
                        ? null
                        : () {
                            final groups =
                                List<_ScanImageGroup>.from(_groups);
                            Navigator.pop(context);
                            widget.onComplete(groups);
                          },
                    child: Text('核對入庫 ($_totalResults)'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _LogStatus { scanning, done, error }

class _ScanLogEntry {
  const _ScanLogEntry({required this.label, required this.status});
  final String label;
  final _LogStatus status;
}

// ─────────────────────────────────────────────────────────────────────────────

class _FabricPageState extends State<FabricPage>
    with SingleTickerProviderStateMixin {
  final DatabaseService _dbService = DatabaseService();
  final AiFabricScanService _aiFabricScanService = AiFabricScanService();

  final List<String> _categories = ['All', 'Cotton', 'Linen', 'Wool', 'Other'];

  late TabController _tabController;
  bool _isUploading = false;
  bool _isAiScanning = false; // 🌟 新增：用於顯示 AI 掃描中的動畫

  // === 1. 新增：檢視與排序狀態變數 ===
  bool _isGridView = true; // 預設使用網格視圖 (比較美觀)
  bool _sortAscending = true; // 預設 A-Z 排序

  // === 搜尋 ===
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // === 所有布料（用於重覆名稱檢查）===
  List<MaterialItem> _allFabrics = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _aiFabricScanService.close();
    super.dispose();
  }

  Future<String?> _uploadImage(Uint8List fileData) async {
    try {
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final Reference storageRef = FirebaseStorage.instance
          .ref()
          .child('fabric_images')
          .child(fileName);
      final SettableMetadata metadata = SettableMetadata(
        contentType: 'image/jpeg',
      );
      final UploadTask uploadTask = storageRef.putData(fileData, metadata);
      final TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint('Error uploading image: $e');
      return null;
    }
  }

  // === 新增/編輯 對話框 ===
  void _showAddEditDialog({MaterialItem? item}) {
    // 將 Controller 定義在這裡，以便 AI 函數可以直接修改它們
    final nameController = TextEditingController(text: item?.name ?? '');
    final costController = TextEditingController(
      text: item?.costPerUnit.toString() ?? '',
    );

    final unitController = TextEditingController(text: item?.unit ?? 'm');
    final retailPriceController = TextEditingController(
      text: item?.retailPrice.toString() ?? '',
    );
    final colorController = TextEditingController(text: item?.color ?? '');
    bool isOnline = item?.isOnline ?? false;

    String selectedCategory = item?.category ?? 'Cotton';
    if (selectedCategory == 'All' || !_categories.contains(selectedCategory)) {
      selectedCategory = 'Other';
    }

    Uint8List? pickedImageBytes;
    String? currentImageUrl = item?.imageUrl;
    Future<String?>? backgroundUploadTask;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // 🌟 === AI 掃描與解析邏輯 === 🌟
          Future<void> runAiScan(Uint8List imageBytes, String mimeType) async {
            setDialogState(() => _isAiScanning = true);
            try {
              final result = await _aiFabricScanService.scanFabricLabel(
                imageBytes: imageBytes,
                mimeType: mimeType,
              );

              setDialogState(() {
                if (result.name.isNotEmpty && nameController.text.isEmpty) {
                  nameController.text = result.name;
                }
                if (_categories.contains(result.category)) {
                  selectedCategory = result.category;
                }
                if (result.color.isNotEmpty && colorController.text.isEmpty) {
                  colorController.text = result.color;
                }
              });

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✨ AI 已自動填入標籤資訊！'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            } catch (e) {
              debugPrint('AI Scan Error: $e');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('AI 辨識失敗：$e'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            } finally {
              setDialogState(() => _isAiScanning = false);
            }
          }
          // 🌟 === AI 邏輯結束 === 🌟

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 32,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 680,
                maxHeight: MediaQuery.of(context).size.height * 0.88,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item == null
                                ? AppLocalizations.of(
                                    context,
                                  ).addFabric.toUpperCase()
                                : AppLocalizations.of(
                                    context,
                                  ).editFabric.toUpperCase(),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        // 🌟 如果 AI 正在掃描，顯示進度指示器
                        if (_isAiScanning)
                          const Padding(
                            padding: EdgeInsets.only(right: 16.0),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: (_isUploading || _isAiScanning)
                              ? null
                              : () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: GestureDetector(
                              onTap: _isAiScanning ? null : () async {
                                final ImagePicker picker = ImagePicker();
                                final XFile? image = await picker.pickImage(
                                  source: ImageSource.gallery,
                                  maxWidth: 1024,
                                  imageQuality: 85,
                                );

                                if (image != null) {
                                  final bytes = await image.readAsBytes();
                                  // 根據副檔名判斷 MIME type
                                  final ext = image.name
                                      .split('.')
                                      .last
                                      .toLowerCase();
                                  final mimeType = switch (ext) {
                                    'png' => 'image/png',
                                    'gif' => 'image/gif',
                                    'webp' => 'image/webp',
                                    'heic' || 'heif' => 'image/heic',
                                    _ => 'image/jpeg',
                                  };
                                  backgroundUploadTask = _uploadImage(bytes);
                                  setDialogState(() {
                                    pickedImageBytes = bytes;
                                  });

                                  // 🌟 照片選取完成後，背景觸發 AI 掃描
                                  // 如果是新增布料，或是原本沒有名字，才讓 AI 幫忙填寫
                                  if (item == null ||
                                      nameController.text.isEmpty) {
                                    runAiScan(bytes, mimeType);
                                  }
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
                                      ? DecorationImage(
                                          image: MemoryImage(pickedImageBytes!),
                                          fit: BoxFit.cover,
                                        )
                                      : (currentImageUrl != null &&
                                                currentImageUrl.isNotEmpty
                                            ? DecorationImage(
                                                image: NetworkImage(
                                                  currentImageUrl,
                                                ),
                                                fit: BoxFit.cover,
                                              )
                                            : null),
                                ),
                                child: _isAiScanning
                                    ? Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.55,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: const Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            ),
                                            SizedBox(height: 6),
                                            Text(
                                              'AI Scanning…',
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : (pickedImageBytes == null &&
                                          (currentImageUrl == null ||
                                              currentImageUrl.isEmpty))
                                    ? Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          IconText(
                                            Icons.add_a_photo,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.7),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Add Photo \n& AI Scan',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            ),
                                          ),
                                        ],
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          SwitchListTile(
                            title: Text(
                              AppLocalizations.of(context).availableOnline,
                            ),
                            subtitle: Text(
                              isOnline
                                  ? AppLocalizations.of(
                                      context,
                                    ).visibleToCustomers
                                  : AppLocalizations.of(
                                      context,
                                    ).hiddenFromStore,
                            ),
                            value: isOnline,
                            activeThumbColor: Colors.green,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (val) =>
                                setDialogState(() => isOnline = val),
                          ),
                          const Divider(),

                          DropdownButtonFormField<String>(
                            initialValue: selectedCategory,
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(
                                context,
                              ).categoryLabel,
                            ),
                            items: _categories
                                .where((c) => c != 'All')
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(c),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) =>
                                setDialogState(() => selectedCategory = val!),
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: nameController,
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(context).nameLabel,
                              hintText: 'e.g. VBC AR2267 31 Blue',
                            ),
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: colorController,
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(
                                context,
                              ).colourLabel,
                              hintText: AppLocalizations.of(
                                context,
                              ).colourPlaceholder,
                            ),
                            inputFormatters: [
                              TextInputFormatter.withFunction(
                                (oldValue, newValue) => newValue.copyWith(
                                  text: newValue.text.toUpperCase(),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: costController,
                                  decoration: InputDecoration(
                                    labelText: AppLocalizations.of(
                                      context,
                                    ).costPrice,
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: retailPriceController,
                                  decoration: InputDecoration(
                                    labelText: AppLocalizations.of(
                                      context,
                                    ).retailPrice,
                                    suffixText: '\$',
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: unitController,
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(context).unitLabel,
                            ),
                            inputFormatters: [
                              TextInputFormatter.withFunction(
                                (oldValue, newValue) => newValue.copyWith(
                                  text: newValue.text.toUpperCase(),
                                ),
                              ),
                            ],
                          ),

                          if (_isUploading)
                            Padding(
                              padding: EdgeInsets.only(top: 16.0),
                              child: Column(
                                children: [
                                  const LinearProgressIndicator(),
                                  SizedBox(height: 4),
                                  Text(
                                    'Saving data...',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: (_isUploading || _isAiScanning)
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('CANCEL'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: (_isUploading || _isAiScanning)
                              ? null
                              : () async {
                                  final dialogNavigator = Navigator.of(context);
                                  final scaffoldMessenger =
                                      ScaffoldMessenger.of(this.context);

                                  // 重覆名稱檢查
                                  final inputName = nameController.text
                                      .trim()
                                      .toUpperCase();
                                  if (inputName.isEmpty) {
                                    scaffoldMessenger.showSnackBar(
                                      const SnackBar(
                                        content: Text('請輸入布料名稱'),
                                        backgroundColor: Colors.orange,
                                      ),
                                    );
                                    return;
                                  }
                                  final isDuplicate = _allFabrics.any(
                                    (f) =>
                                        f.name.trim().toUpperCase() ==
                                            inputName &&
                                        f.id != (item?.id ?? ''),
                                  );
                                  if (isDuplicate) {
                                    scaffoldMessenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '布料名稱「$inputName」已存在，請使用不同名稱',
                                        ),
                                        backgroundColor: Colors.orange,
                                      ),
                                    );
                                    return;
                                  }

                                  setDialogState(() => _isUploading = true);

                                  try {
                                    String? finalImageUrl = currentImageUrl;

                                    if (backgroundUploadTask != null) {
                                      finalImageUrl =
                                          await backgroundUploadTask!.timeout(
                                            const Duration(seconds: 20),
                                            onTimeout: () => null,
                                          );

                                      if (finalImageUrl == null) {
                                        throw Exception(
                                          'Image upload failed or timed out. Please try again.',
                                        );
                                      }
                                    }

                                    final newItem = MaterialItem(
                                      id: item?.id ?? '',
                                      name: nameController.text,
                                      costPerUnit:
                                          double.tryParse(
                                            costController.text,
                                          ) ??
                                          0,
                                      stock: item?.stock ?? 0,
                                      reorderLevel: 0,
                                      unit: unitController.text,
                                      imageUrl: finalImageUrl,
                                      category: selectedCategory,
                                      retailPrice:
                                          double.tryParse(
                                            retailPriceController.text,
                                          ) ??
                                          0,
                                      isOnline: isOnline,
                                      color: colorController.text.trim(),
                                    );

                                    if (item == null) {
                                      await _dbService.addMaterial(newItem);
                                    } else {
                                      await _dbService.updateMaterial(newItem);
                                    }

                                    if (mounted) dialogNavigator.pop();
                                  } catch (e) {
                                    debugPrint('Error saving material: $e');
                                    if (mounted) {
                                      scaffoldMessenger.showSnackBar(
                                        SnackBar(
                                          content: Text('Save failed: $e'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setDialogState(
                                        () => _isUploading = false,
                                      );
                                    }
                                  }
                                },
                          child: Text(
                            _isUploading
                                ? AppLocalizations.of(
                                    context,
                                  ).savingButton.toUpperCase()
                                : AppLocalizations.of(
                                    context,
                                  ).saveButton.toUpperCase(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _startBatchScan() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BatchScanManagerDialog(
        fabricScanService: _aiFabricScanService,
        onComplete: _showBatchReviewDialog,
      ),
    );
  }

  void _showBatchReviewDialog(List<_ScanImageGroup> groups) {
    const validCats = ['Cotton', 'Linen', 'Wool', 'Other'];
    final rows = [
      for (final g in groups)
        for (final r in g.results)
          _BatchRow.fromResult(r, imageBytes: g.imageBytes),
    ];
    bool isSaving = false;
    int saveProgress = 0;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          bool nameExistsInDb(String name) =>
              name.isNotEmpty &&
              _allFabrics.any(
                (f) => f.name.trim().toUpperCase() == name.toUpperCase(),
              );

          bool nameExistsInBatch(int idx) {
            final name = rows[idx].nameCtrl.text.trim().toUpperCase();
            if (name.isEmpty) return false;
            for (int j = 0; j < rows.length; j++) {
              if (j != idx &&
                  rows[j].nameCtrl.text.trim().toUpperCase() == name) {
                return true;
              }
            }
            return false;
          }

          // Auto-uncheck: empty name or DB duplicate
          for (final row in rows) {
            final name = row.nameCtrl.text.trim();
            if ((name.isEmpty || nameExistsInDb(name)) && row.checked) {
              row.checked = false;
            }
          }

          bool rowWillSave(int i) =>
              rows[i].checked &&
              rows[i].nameCtrl.text.trim().isNotEmpty &&
              !nameExistsInDb(rows[i].nameCtrl.text.trim());
          final willSaveCount =
              List.generate(rows.length, (i) => i).where(rowWillSave).length;
          final cs = Theme.of(ctx).colorScheme;

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 780,
                maxHeight: MediaQuery.of(ctx).size.height * 0.9,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title + live counter
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Batch AI Scan Results', // l10n: batchScanResults
                                style: Theme.of(ctx).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isSaving
                                    ? '正在入庫 $saveProgress / $willSaveCount …'
                                    : '共辨識 ${rows.length} 筆，將入庫 $willSaveCount 筆',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: willSaveCount > 0
                                      ? cs.primary
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed:
                              isSaving ? null : () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 12),
                  // Column headers
                  Padding(
                    padding: const EdgeInsets.fromLTRB(52, 0, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '名稱',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 100,
                              child: Text(
                                '類別',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 48,
                              child: Text(
                                '上架',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '顏色',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 55,
                              child: Text(
                                '單位',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 68,
                              child: Text(
                                '成本',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 68,
                              child: Text(
                                '零售價',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Editable item list
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: cs.outlineVariant),
                      itemBuilder: (_, i) {
                        final row = rows[i];
                        final name = row.nameCtrl.text.trim();
                        final isEmpty = name.isEmpty;
                        final dbDup = nameExistsInDb(name);
                        final batchDup = nameExistsInBatch(i);

                        return Container(
                          color: isEmpty
                              ? cs.errorContainer.withValues(alpha: 0.25)
                              : null,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Checkbox pinned to top-left
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: SizedBox(
                                  width: 40,
                                  child: Checkbox(
                                    value: row.checked,
                                    onChanged: isEmpty || isSaving || dbDup
                                        ? null
                                        : (v) => setDialogState(
                                              () => row.checked = v!,
                                            ),
                                  ),
                                ),
                              ),
                              // Source image thumbnail
                              if (row.sourceImageBytes != null)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 6,
                                    right: 8,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.memory(
                                      row.sourceImageBytes!,
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              // Two-row content block
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // ── Row 1: Name · Category · isOnline ──
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Name + dup badges
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              TextField(
                                                controller: row.nameCtrl,
                                                enabled: !isSaving,
                                                onChanged: (_) =>
                                                    setDialogState(() {}),
                                                style: const TextStyle(
                                                    fontSize: 13),
                                                decoration: InputDecoration(
                                                  isDense: true,
                                                  contentPadding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                    horizontal: 8,
                                                    vertical: 8,
                                                  ),
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                    borderSide: BorderSide(
                                                      color: isEmpty
                                                          ? cs.error
                                                          : cs.outline,
                                                    ),
                                                  ),
                                                  enabledBorder:
                                                      OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                    borderSide: BorderSide(
                                                      color: isEmpty
                                                          ? cs.error
                                                          : cs.outline,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              if (dbDup || batchDup) ...[
                                                const SizedBox(height: 3),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: cs.tertiaryContainer,
                                                    borderRadius:
                                                        BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    dbDup ? '已存在' : '批次重複',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color:
                                                          cs.onTertiaryContainer,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Category dropdown
                                        SizedBox(
                                          width: 100,
                                          child: DropdownButtonFormField<String>(
                                            initialValue: row.category,
                                            isDense: true,
                                            isExpanded: true,
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 8,
                                              ),
                                              border: OutlineInputBorder(),
                                            ),
                                            items: validCats
                                                .map(
                                                  (c) => DropdownMenuItem(
                                                    value: c,
                                                    child: Text(
                                                      c,
                                                      style: const TextStyle(
                                                          fontSize: 12),
                                                    ),
                                                  ),
                                                )
                                                .toList(),
                                            onChanged: isSaving
                                                ? null
                                                : (v) => setDialogState(
                                                      () => row.category = v!,
                                                    ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // isOnline toggle
                                        SizedBox(
                                          width: 48,
                                          child: Switch(
                                            value: row.isOnline,
                                            onChanged: isSaving
                                                ? null
                                                : (v) => setDialogState(
                                                      () => row.isOnline = v,
                                                    ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    // ── Row 2: Colour · Unit · Cost · Retail ──
                                    Row(
                                      children: [
                                        // Colour
                                        Expanded(
                                          child: TextField(
                                            controller: row.colorCtrl,
                                            enabled: !isSaving,
                                            inputFormatters: [
                                              TextInputFormatter.withFunction(
                                                (o, n) => n.copyWith(
                                                  text: n.text.toUpperCase(),
                                                ),
                                              ),
                                            ],
                                            style:
                                                const TextStyle(fontSize: 12),
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              hintText: 'COLOUR',
                                              hintStyle:
                                                  TextStyle(fontSize: 11),
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 7,
                                              ),
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Unit
                                        SizedBox(
                                          width: 55,
                                          child: TextField(
                                            controller: row.unitCtrl,
                                            enabled: !isSaving,
                                            inputFormatters: [
                                              TextInputFormatter.withFunction(
                                                (o, n) => n.copyWith(
                                                  text: n.text.toUpperCase(),
                                                ),
                                              ),
                                            ],
                                            style:
                                                const TextStyle(fontSize: 12),
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 7,
                                              ),
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Cost
                                        SizedBox(
                                          width: 68,
                                          child: TextField(
                                            controller: row.costCtrl,
                                            enabled: !isSaving,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
                                              decimal: true,
                                            ),
                                            style:
                                                const TextStyle(fontSize: 12),
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 7,
                                              ),
                                              border: OutlineInputBorder(),
                                              prefixText: '\$ ',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Retail price
                                        SizedBox(
                                          width: 68,
                                          child: TextField(
                                            controller: row.retailCtrl,
                                            enabled: !isSaving,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
                                              decimal: true,
                                            ),
                                            style:
                                                const TextStyle(fontSize: 12),
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 7,
                                              ),
                                              border: OutlineInputBorder(),
                                              prefixText: '\$ ',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  // Footer
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed:
                              isSaving ? null : () => Navigator.pop(ctx),
                          child: const Text('CANCEL'),
                        ),
                        if (isSaving) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LinearProgressIndicator(
                                  value: willSaveCount > 0
                                      ? saveProgress / willSaveCount
                                      : null,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '正在入庫 $saveProgress / $willSaveCount',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                        ] else
                          const Spacer(),
                        FilledButton.icon(
                          icon: isSaving
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: cs.onPrimary,
                                  ),
                                )
                              : const Icon(
                                  Icons.download_done_rounded,
                                  size: 18,
                                ),
                          label: Text(
                            isSaving
                                ? '入庫中…'
                                : '全部入庫 ($willSaveCount 筆)', // l10n: batchImport
                          ),
                          onPressed: (isSaving || willSaveCount == 0)
                              ? null
                              : () async {
                                  final toSave = List.generate(
                                    rows.length,
                                    (i) => i,
                                  ).where(rowWillSave).toList();
                                  final totalToSave = toSave.length;
                                  setDialogState(() {
                                    isSaving = true;
                                    saveProgress = 0;
                                  });

                                  // Upload each unique source image once,
                                  // reusing the URL for all rows from the
                                  // same scan image.
                                  final Map<Uint8List, String?> imageUrlCache =
                                      {};
                                  for (final i in toSave) {
                                    final bytes = rows[i].sourceImageBytes;
                                    if (bytes != null &&
                                        !imageUrlCache.containsKey(bytes)) {
                                      imageUrlCache[bytes] =
                                          await _uploadImage(bytes);
                                    }
                                  }

                                  int saved = 0;
                                  int failed = 0;

                                  for (final i in toSave) {
                                    try {
                                      final imageUrl = rows[i].sourceImageBytes
                                          != null
                                          ? imageUrlCache[rows[i]
                                                .sourceImageBytes]
                                          : null;
                                      await _dbService.addMaterial(
                                        MaterialItem(
                                          id: '',
                                          name: rows[i].nameCtrl.text.trim(),
                                          category: rows[i].category,
                                          color: rows[i].colorCtrl.text.trim(),
                                          costPerUnit:
                                              double.tryParse(
                                                rows[i].costCtrl.text,
                                              ) ??
                                              0,
                                          retailPrice:
                                              double.tryParse(
                                                rows[i].retailCtrl.text,
                                              ) ??
                                              0,
                                          unit: rows[i].unitCtrl.text
                                                  .trim()
                                                  .isNotEmpty
                                              ? rows[i].unitCtrl.text.trim()
                                              : 'm',
                                          isOnline: rows[i].isOnline,
                                          imageUrl: imageUrl,
                                          stock: 0,
                                          reorderLevel: 0,
                                        ),
                                      );
                                      saved++;
                                    } catch (e) {
                                      debugPrint('Batch add error [$i]: $e');
                                      failed++;
                                    }
                                    if (ctx.mounted) {
                                      setDialogState(() => saveProgress++);
                                    }
                                  }

                                  if (!ctx.mounted) return;
                                  Navigator.pop(ctx);

                                  final skipped =
                                      rows.length - totalToSave + failed;
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          skipped > 0
                                              ? '成功入庫 $saved 筆，跳過 $skipped 筆'
                                              : '成功入庫 $saved 筆',
                                        ),
                                        backgroundColor: Theme.of(
                                          context,
                                        ).colorScheme.tertiary,
                                      ),
                                    );
                                  }
                                },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) {
      for (final row in rows) {
        row.nameCtrl.dispose();
        row.colorCtrl.dispose();
        row.costCtrl.dispose();
        row.retailCtrl.dispose();
        row.unitCtrl.dispose();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).fabricTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.document_scanner),
            tooltip: 'Batch AI Scan', // l10n: batchScan
            onPressed: _startBatchScan,
          ),
          PopupMenuButton<bool>(
            icon: const IconText(Icons.sort_by_alpha),
            tooltip: AppLocalizations.of(context).sortOrder,
            onSelected: (bool isAscending) {
              setState(() => _sortAscending = isAscending);
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<bool>>[
              PopupMenuItem<bool>(
                value: true,
                child: Row(
                  children: [
                    IconText(Icons.arrow_downward, size: 18),
                    SizedBox(width: 8),
                    Text(AppLocalizations.of(context).sortNameAZ),
                  ],
                ),
              ),
              PopupMenuItem<bool>(
                value: false,
                child: Row(
                  children: [
                    IconText(Icons.arrow_upward, size: 18),
                    SizedBox(width: 8),
                    Text(AppLocalizations.of(context).sortNameZA),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: IconText(_isGridView ? Icons.view_list : Icons.grid_view),
            tooltip: _isGridView
                ? AppLocalizations.of(context).switchToList
                : AppLocalizations.of(context).switchToGrid,
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: AppLocalizations.of(context).categoryAll),
            Tab(text: AppLocalizations.of(context).categoryCotton),
            Tab(text: AppLocalizations.of(context).categoryLinen),
            Tab(text: AppLocalizations.of(context).categoryWool),
            Tab(text: AppLocalizations.of(context).categoryOther),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.black),
              onChanged: (value) =>
                  setState(() => _searchQuery = value.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search fabric name...',
                hintStyle: TextStyle(color: Colors.grey[600]),
                prefixIcon: const Icon(Icons.search, color: Colors.black54),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.black54),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<MaterialItem>>(
              stream: _dbService.getInventoryStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allFabrics = snapshot.data ?? [];
                _allFabrics = allFabrics;

                return TabBarView(
                  controller: _tabController,
                  children: _categories.map((category) {
                    var filteredFabrics = category == 'All'
                        ? List<MaterialItem>.from(allFabrics)
                        : allFabrics
                              .where((f) => f.category == category)
                              .toList();

                    if (_searchQuery.isNotEmpty) {
                      filteredFabrics = filteredFabrics
                          .where(
                            (f) => f.name.toLowerCase().contains(_searchQuery),
                          )
                          .toList();
                    }

                    if (filteredFabrics.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconText(
                              Icons.inventory_2_outlined,
                              size: 64,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No $category fabrics found',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    filteredFabrics.sort((a, b) {
                      int cmp = a.name.toLowerCase().compareTo(
                        b.name.toLowerCase(),
                      );
                      return _sortAscending ? cmp : -cmp;
                    });

                    if (_isGridView) {
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          int crossAxisCount = (constraints.maxWidth / 180)
                              .floor();
                          if (crossAxisCount < 2) crossAxisCount = 2;

                          return GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  childAspectRatio: 0.75,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                ),
                            itemCount: filteredFabrics.length,
                            itemBuilder: (context, index) {
                              final fabric = filteredFabrics[index];

                              return Card(
                                clipBehavior: Clip.antiAlias,
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: InkWell(
                                  onTap: () => _showAddEditDialog(item: fabric),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            (fabric.imageUrl != null &&
                                                    fabric.imageUrl!.isNotEmpty)
                                                ? Image.network(
                                                    fabric.imageUrl!,
                                                    fit: BoxFit.cover,
                                                  )
                                                : Container(
                                                    color: Colors.grey[200],
                                                    child: IconText(
                                                      Icons.image_not_supported,
                                                      size: 40,
                                                      color: Colors.grey[400],
                                                    ),
                                                  ),

                                            if (fabric.isOnline)
                                              Positioned(
                                                top: 8,
                                                left: 8,
                                                child: Container(
                                                  padding: const EdgeInsets.all(
                                                    4,
                                                  ),
                                                  decoration:
                                                      const BoxDecoration(
                                                        color: Colors.white,
                                                        shape: BoxShape.circle,
                                                      ),
                                                  child: const IconText(
                                                    Icons.public,
                                                    size: 14,
                                                    color: Colors.green,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              fabric.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '\$${fabric.retailPrice.toStringAsFixed(0)}',
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).primaryColor,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  fabric.category,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurface
                                                        .withValues(
                                                          alpha: 0.55,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredFabrics.length,
                      separatorBuilder: (_, separatorIndex) => const Divider(),
                      itemBuilder: (context, index) {
                        final fabric = filteredFabrics[index];

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          leading: GestureDetector(
                            onTap: () {
                              if (fabric.imageUrl != null &&
                                  fabric.imageUrl!.isNotEmpty) {
                                showDialog(
                                  context: context,
                                  builder: (_) => Dialog(
                                    child: Image.network(fabric.imageUrl!),
                                  ),
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
                                image:
                                    (fabric.imageUrl != null &&
                                        fabric.imageUrl!.isNotEmpty)
                                    ? DecorationImage(
                                        image: NetworkImage(fabric.imageUrl!),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child:
                                  (fabric.imageUrl == null ||
                                      fabric.imageUrl!.isEmpty)
                                  ? const IconText(
                                      Icons.texture,
                                      color: Colors.grey,
                                    )
                                  : null,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  fabric.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (fabric.isOnline)
                                Tooltip(
                                  message: AppLocalizations.of(
                                    context,
                                  ).onlineLabel,
                                  child: const IconText(
                                    Icons.public,
                                    size: 16,
                                    color: Colors.green,
                                  ),
                                )
                              else
                                Tooltip(
                                  message: AppLocalizations.of(
                                    context,
                                  ).offlineLabel,
                                  child: const IconText(
                                    Icons.public_off,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    'Cost: \$${fabric.costPerUnit.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.7),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Retail: \$${fabric.retailPrice.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                      .withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  fabric.category,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const IconText(
                                  Icons.edit,
                                  color: Colors.blue,
                                ),
                                onPressed: () =>
                                    _showAddEditDialog(item: fabric),
                              ),
                              IconButton(
                                icon: const IconText(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Text(
                                        AppLocalizations.of(
                                          context,
                                        ).deleteFabric,
                                      ),
                                      content: Text(
                                        '${AppLocalizations.of(context).deleteFabric}: ${fabric.name}?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: Text(
                                            AppLocalizations.of(
                                              context,
                                            ).cancelButton,
                                          ),
                                        ),
                                        ElevatedButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                          ),
                                          child: Text(
                                            AppLocalizations.of(
                                              context,
                                            ).deleteButton,
                                          ),
                                        ),
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
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
        child: const IconText(Icons.add),
      ),
    );
  }
}
