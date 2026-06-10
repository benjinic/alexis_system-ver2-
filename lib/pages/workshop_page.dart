import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/workshop_order.dart';
import '../models/workshop_status.dart';
import '../services/database_service.dart';
import '../components/workshop_card.dart';

class WorkshopPage extends StatefulWidget {
  final int initialScrollIndex; // 支援外部傳入初始位置

  const WorkshopPage({super.key, this.initialScrollIndex = 0});

  @override
  State<WorkshopPage> createState() => _WorkshopPageState();
}

class _WorkshopPageState extends State<WorkshopPage> {
  bool _showArchived = false;
  final DatabaseService _dbService = DatabaseService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';

  // 定義看板的欄位
  final List<Map<String, dynamic>> _stages = [
    {
      'id': WorkshopStatus.measuring,
      'label': 'Measuring',
      'color': Colors.blue,
    },
    {'id': WorkshopStatus.cutting, 'label': 'Cutting', 'color': Colors.orange},
    {'id': WorkshopStatus.sewing, 'label': 'Sewing', 'color': Colors.purple},
    {
      'id': WorkshopStatus.finishing,
      'label': 'Finishing',
      'color': Colors.indigo,
    },
    {
      'id': WorkshopStatus.completed,
      'label': 'Completed',
      'color': Colors.green,
    },
  ];

  @override
  void initState() {
    super.initState();
    // 初始捲動到指定欄位
    if (widget.initialScrollIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        double offset = widget.initialScrollIndex * 336.0;
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            offset,
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _updateOrderStatus(
    WorkshopOrder order,
    WorkshopStatus newStatus,
  ) async {
    final oldStatus = order.status;
    final oldProgress = order.progress;
    int newProgress = 0;

    switch (newStatus) {
      case WorkshopStatus.measuring:
        newProgress = 0;
        break;
      case WorkshopStatus.cutting:
        newProgress = 25;
        break;
      case WorkshopStatus.sewing:
        newProgress = 50;
        break;
      case WorkshopStatus.finishing:
        newProgress = 80;
        break;
      case WorkshopStatus.completed:
        newProgress = 100;
        break;
      case WorkshopStatus.archived:
        newProgress = 100;
        break;
    }

    await _dbService.updateWorkshopOrder(
      order.copyWith(
        status: newStatus,
        progress: newProgress,
        updatedAt: DateTime.now(),
      ),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Moved to ${newStatus.label}'),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: Colors.yellow,
            onPressed: () async {
              await _dbService.updateWorkshopOrder(
                order.copyWith(
                  status: oldStatus,
                  progress: oldProgress,
                  updatedAt: DateTime.now(),
                ),
              );
            },
          ),
        ),
      );
    }
  }

  void _toggleArchive(WorkshopOrder order, bool archive) async {
    await _dbService.updateWorkshopOrder(
      order.copyWith(
        status: archive ? WorkshopStatus.archived : WorkshopStatus.completed,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _toggleFabricOrdered(WorkshopOrder order) async {
    await _dbService.updateWorkshopOrder(
      order.copyWith(
        isFabricOrdered: !order.isFabricOrdered,
        updatedAt: DateTime.now(),
      ),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(order.isFabricOrdered ? '布料標記為未訂購' : '布料已標記為已訂購'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // === 3. 下拉更新邏輯 ===
  Future<void> _handleRefresh() async {
    // 由於使用 StreamBuilder，其實只要 setState 觸發重建即可
    // 這裡加一點延遲模擬讀取感
    await Future.delayed(const Duration(milliseconds: 800));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived ? 'Archived History' : 'Workshop Board'),
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _showArchived = !_showArchived),
            icon: Icon(
              _showArchived ? Icons.view_kanban : Icons.archive,
              color: Colors.white,
            ),
            label: Text(
              _showArchived ? 'Back to Board' : 'Archive',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      // === 核心修改：使用 RefreshIndicator 包裹 CustomScrollView ===
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: StreamBuilder<List<WorkshopOrder>>(
          stream: _dbService.getWorkshopOrdersStream(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            // 這裡可以不顯示 Loading，保留舊畫面體驗更好，或者放一個 LinearProgressIndicator
            final allOrders = snapshot.data ?? [];

            final filteredOrders = allOrders.where((o) {
              final matchesQuery =
                  o.customer.toLowerCase().contains(_searchQuery) ||
                  o.item.toLowerCase().contains(_searchQuery) ||
                  o.orderId.contains(_searchQuery); // 支援搜尋訂單號
              final matchesStatus = _showArchived
                  ? o.status == WorkshopStatus.archived
                  : o.status != WorkshopStatus.archived;
              return matchesQuery && matchesStatus;
            }).toList();

            // 如果是封存模式，顯示簡單列表
            if (_showArchived) {
              return ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: filteredOrders.length,
                itemBuilder: (context, index) {
                  final order = filteredOrders[index];
                  return Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.check_circle,
                        color: Colors.grey,
                      ),
                      title: Text(
                        order.customer,
                        style: const TextStyle(
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      subtitle: Text('${order.itemType} #${order.orderId}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.unarchive),
                        onPressed: () => _toggleArchive(order, false),
                      ),
                    ),
                  );
                },
              );
            }

            // 看板模式：使用 CustomScrollView 來支援下拉更新
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(), // 確保隨時可下拉
              slivers: [
                // 1. 搜尋列與標題 (固定在頂部，不會橫向捲動)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search ticket #ID, customer or item...',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () => setState(() {
                                      _searchController.clear();
                                      _searchQuery = '';
                                    }),
                                  )
                                : null,
                          ),
                          onChanged: (val) =>
                              setState(() => _searchQuery = val.toLowerCase()),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            const Icon(Icons.dashboard_customize, size: 28),
                            const SizedBox(width: 12),
                            Text(
                              'Production Flow',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            Text(
                              '${filteredOrders.length} active tasks',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. 看板內容 (填滿剩餘空間)
                SliverFillRemaining(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      scrollDirection: Axis.horizontal,
                      itemCount: _stages.length,
                      separatorBuilder: (ctx, i) => const SizedBox(width: 16),
                      itemBuilder: (context, index) {
                        final stage = _stages[index];
                        final stageOrders =
                            filteredOrders
                                .where(
                                  (o) =>
                                      o.status == stage['id'] as WorkshopStatus,
                                )
                                .toList()
                              ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

                        return _buildKanbanColumn(
                          stage['id'] as WorkshopStatus,
                          stage['label'],
                          stage['color'],
                          stageOrders,
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // 建構單一看板欄位
  Widget _buildKanbanColumn(
    WorkshopStatus stageId,
    String title,
    MaterialColor color,
    List<WorkshopOrder> orders,
  ) {
    return DragTarget<WorkshopOrder>(
      onWillAccept: (data) => data != null && data.status != stageId,
      onAccept: (order) => _updateOrderStatus(order, stageId),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return Container(
          width: 320,
          decoration: BoxDecoration(
            color: isHovering ? color[50] : Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isHovering ? color : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              // 欄位標題 + 數量
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color[100],
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 12, color: color[700]),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color[900],
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${orders.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 訂單列表
              Expanded(
                child: orders.isEmpty
                    ? Center(
                        child: Text(
                          'No tasks',
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: orders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final order = orders[index];

                          // 定義下一個階段 (用於快速移動按鈕)
                          WorkshopStatus? nextStatus;
                          switch (order.status) {
                            case WorkshopStatus.measuring:
                              nextStatus = WorkshopStatus.cutting;
                              break;
                            case WorkshopStatus.cutting:
                              nextStatus = WorkshopStatus.sewing;
                              break;
                            case WorkshopStatus.sewing:
                              nextStatus = WorkshopStatus.finishing;
                              break;
                            case WorkshopStatus.finishing:
                              nextStatus = WorkshopStatus.completed;
                              break;
                            default:
                              nextStatus = null;
                          }

                          return Draggable<WorkshopOrder>(
                            data: order,
                            feedback: SizedBox(
                              width: 300,
                              child: Opacity(
                                opacity: 0.9,
                                child: WorkshopCard(order: order, onTap: () {}),
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: 0.3,
                              child: WorkshopCard(order: order, onTap: () {}),
                            ),
                            child: WorkshopCard(
                              order: order,
                              // 1. 點擊卡片本體 -> 開啟詳情 (預設檢視模式)
                              onTap: () => _showOrderDetails(context, order),

                              // 2. 點擊編輯按鈕 -> 開啟詳情 (並自動進入編輯模式)
                              onEdit: () => _showOrderDetails(
                                context,
                                order,
                                initialEditing: true,
                              ),

                              // 3. 點擊下一步 -> 直接更新狀態
                              onNextStage: nextStatus != null
                                  ? () => _updateOrderStatus(order, nextStatus!)
                                  : null,

                              // 4. 封存 -> 封存邏輯
                              onArchive:
                                  order.status == WorkshopStatus.completed
                                  ? () => _toggleArchive(order, true)
                                  : null,
                              onFabricToggle: () => _toggleFabricOrdered(order),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 訂單詳情彈窗
  void _showOrderDetails(
    BuildContext context,
    WorkshopOrder order, {
    bool initialEditing = false,
  }) {
    // 1. 初始化控制器與狀態
    final TextEditingController itemController = TextEditingController(
      text: order.item,
    );
    final TextEditingController notesController = TextEditingController(
      text: order.notes,
    );

    DateTime selectedDate = order.dueDate;
    bool isEditing = initialEditing; // 根據傳入參數決定是否直接進入編輯模式

    showDialog(
      context: context,
      barrierDismissible: !isEditing, // 編輯中不允許點擊外部關閉，怕誤觸
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // === 頂部標題區 ===
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isEditing ? 'Edit Order' : 'Job Details',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (order.orderId.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Ticket #${order.orderId}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[800],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            // 關閉按鈕
                            if (!isEditing)
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(context),
                              ),
                          ],
                        ),
                        const Divider(height: 32),

                        // === 1. 客戶名稱 (唯讀) ===
                        _buildLabel('Customer'),
                        Text(
                          order.customer,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // === 2. 款式欄位 (Item Style) ===
                        _buildLabel('Item Style / Description'),
                        if (isEditing)
                          TextField(
                            controller: itemController,
                            decoration: InputDecoration(
                              hintText: 'e.g. 3-Piece Suit, VBC Fabric...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              prefixIcon: const Icon(Icons.checkroom, size: 20),
                            ),
                          )
                        else
                          Text(
                            order.item,
                            style: const TextStyle(fontSize: 16),
                          ),
                        const SizedBox(height: 20),

                        // === 3. 日期修改 (Date Picker) ===
                        _buildLabel('Due Date'),
                        InkWell(
                          onTap: isEditing
                              ? () async {
                                  final DateTime? picked = await showDatePicker(
                                    context: context,
                                    initialDate: selectedDate,
                                    firstDate: DateTime.now().subtract(
                                      const Duration(days: 365),
                                    ),
                                    lastDate: DateTime.now().add(
                                      const Duration(days: 365),
                                    ),
                                  );
                                  if (picked != null) {
                                    setDialogState(() => selectedDate = picked);
                                  }
                                }
                              : null,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              border: isEditing
                                  ? Border.all(color: Colors.grey)
                                  : Border.all(color: Colors.transparent),
                              borderRadius: BorderRadius.circular(8),
                              color: isEditing
                                  ? Colors.transparent
                                  : Colors.grey[100],
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  size: 20,
                                  color: Colors.blue[700],
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  DateFormat('yyyy-MM-dd').format(selectedDate),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (isEditing) ...[
                                  const Spacer(),
                                  const Icon(
                                    Icons.edit,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // === 4. 備註欄位 (Notes) ===
                        _buildLabel('Notes / Measurements'),
                        if (isEditing)
                          TextField(
                            controller: notesController,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: 'Add specific instructions here...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.all(12),
                            ),
                          )
                        else
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange[100]!),
                            ),
                            child: Text(
                              order.notes.isEmpty
                                  ? 'No notes provided.'
                                  : order.notes,
                              style: TextStyle(
                                color: Colors.brown[800],
                                height: 1.4,
                              ),
                            ),
                          ),

                        const SizedBox(height: 32),

                        // === 底部按鈕區 ===
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (isEditing)
                              TextButton(
                                onPressed: () {
                                  // 取消編輯：恢復原始數值
                                  setDialogState(() {
                                    isEditing = false;
                                    itemController.text = order.item;
                                    notesController.text = order.notes;
                                    selectedDate = order.dueDate;
                                  });
                                  // 如果是原本從外部直接進來編輯的，取消就是關閉視窗
                                  if (initialEditing) {
                                    Navigator.pop(context);
                                  }
                                },
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () async {
                                if (isEditing) {
                                  // === 修改開始：加入錯誤捕捉 ===
                                  try {
                                    // 顯示讀取圈圈，讓使用者知道系統正在處理
                                    showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (c) => const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );

                                    // 執行資料庫更新
                                    await _dbService.updateWorkshopOrder(
                                      order.copyWith(
                                        item: itemController.text.trim(),
                                        notes: notesController.text.trim(),
                                        dueDate: selectedDate,
                                        updatedAt: DateTime.now(),
                                      ),
                                    );

                                    // 更新成功：關閉讀取圈圈 + 關閉編輯視窗
                                    if (context.mounted) {
                                      Navigator.pop(context); // 關閉讀取圈圈
                                      Navigator.pop(context); // 關閉編輯視窗
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Changes saved successfully!',
                                          ),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    // 發生錯誤：關閉讀取圈圈 + 顯示錯誤訊息
                                    if (context.mounted) {
                                      Navigator.pop(context); // 關閉讀取圈圈
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Error saving: $e',
                                          ), // 顯示具體錯誤原因
                                          backgroundColor: Colors.red,
                                          duration: const Duration(
                                            seconds: 5,
                                          ), // 顯示久一點以便閱讀
                                        ),
                                      );
                                      // 印出詳細錯誤到 Debug Console
                                      print('Save Error: $e');
                                    }
                                  }
                                  // === 修改結束 ===
                                } else {
                                  // 切換為編輯模式
                                  setDialogState(() => isEditing = true);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isEditing
                                    ? Colors.green
                                    : Theme.of(context).primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: Icon(isEditing ? Icons.save : Icons.edit),
                              label: Text(
                                isEditing ? 'Save Changes' : 'Edit Order',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 小輔助 widget
  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
