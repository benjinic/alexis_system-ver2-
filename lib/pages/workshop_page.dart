import 'package:flutter/material.dart';
import '../components/icon_text.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/workshop_order.dart';
import '../models/workshop_status.dart';
import '../services/database_service.dart';
import '../services/pdf_service.dart';
import '../components/workshop_card.dart';

class WorkshopPage extends StatefulWidget {
  final int initialScrollIndex; // 支援外部傳入初始位置

  const WorkshopPage({super.key, this.initialScrollIndex = 0});

  @override
  State<WorkshopPage> createState() => _WorkshopPageState();
}

class _WorkshopPageState extends State<WorkshopPage> {
  static const double _kColumnWidth = 320.0;
  static const double _kColumnGap = 16.0;

  bool _showArchived = false;
  final DatabaseService _dbService = DatabaseService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  String _filterMode = 'all'; // 'all', 'urgent', 'overdue', 'soon'
  String _sortMode = 'dueDate'; // 'dueDate', 'priority', 'customer'
  DateTimeRange? _archiveDateRange;
  final Set<String> _selectedOrderIds = {};
  bool _isSelectionMode = false;
  List<WorkshopOrder> _currentOrders = [];
  final Map<WorkshopStatus, List<String>> _columnOrder = {};

  // 定義看板的欄位
  final List<Map<String, dynamic>> _stages = [
    {
      'id': WorkshopStatus.measuring,
      'labelKey': 'statusMeasuring',
      'color': Colors.blue,
    },
    {
      'id': WorkshopStatus.cutting,
      'labelKey': 'statusCutting',
      'color': Colors.orange,
    },
    {
      'id': WorkshopStatus.sewing,
      'labelKey': 'statusSewing',
      'color': Colors.purple,
    },
    {
      'id': WorkshopStatus.finishing,
      'labelKey': 'statusFinishing',
      'color': Colors.indigo,
    },
    {
      'id': WorkshopStatus.completed,
      'labelKey': 'statusCompleted',
      'color': Colors.green,
    },
  ];

  @override
  void initState() {
    super.initState();
    // 初始捲動到指定欄位
    if (widget.initialScrollIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        double offset = widget.initialScrollIndex * (_kColumnWidth + _kColumnGap);
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
          content: Text(
            '${AppLocalizations.of(context).movedToStatus} ${newStatus.label}',
          ),
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
    final nextStatus = !order.isFabricOrdered;
    final l10n = AppLocalizations.of(context);
    try {
      if (order.orderId.trim().isNotEmpty) {
        await _dbService.updateOrderFabricRequiredItemsStatus(
          orderId: order.orderId,
          isFabricOrdered: nextStatus,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextStatus ? l10n.fabricMarkedOrdered : l10n.fabricMarkedNotOrdered,
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.fabricSyncError('$e')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // === 3. 下拉更新邏輯 ===
  Future<void> _handleRefresh() async {
    await Future.delayed(const Duration(milliseconds: 800));
    setState(() {});
  }

  // 篩選條件
  bool _matchesFilter(WorkshopOrder o) {
    final now = DateTime.now();
    switch (_filterMode) {
      case 'urgent':
        return o.priority == 'urgent';
      case 'overdue':
        return now.isAfter(o.dueDate);
      case 'soon':
        final days = o.dueDate.difference(now).inDays;
        return !now.isAfter(o.dueDate) && days <= 3;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _showArchived
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showNewOrderDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('New Order'),
              backgroundColor: Colors.green,
            ),
      bottomNavigationBar: _isSelectionMode
          ? SafeArea(
              child: Container(
                color: Colors.blue.shade800,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Text(
                      '${_selectedOrderIds.length} selected',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() {
                        _selectedOrderIds.clear();
                        _isSelectionMode = false;
                      }),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _selectedOrderIds.isNotEmpty
                          ? _bulkAdvanceStage
                          : null,
                      icon: const Icon(Icons.fast_forward, size: 16),
                      label: const Text('Advance All'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.blue.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      appBar: AppBar(
        title: Text(
          _showArchived
              ? AppLocalizations.of(context).archivedHistory
              : AppLocalizations.of(context).workshopTitle,
        ),
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () => setState(() {
              _showArchived = !_showArchived;
              _selectedOrderIds.clear();
              _isSelectionMode = false;
              _archiveDateRange = null;
            }),
            icon: IconText(
              _showArchived ? Icons.view_kanban : Icons.archive,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            label: Text(
              _showArchived
                  ? AppLocalizations.of(context).backToBoard
                  : AppLocalizations.of(context).archiveButton,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
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
            _currentOrders = allOrders;

            final filteredOrders = allOrders.where((o) {
              final matchesQuery =
                  o.customer.toLowerCase().contains(_searchQuery) ||
                  o.item.toLowerCase().contains(_searchQuery) ||
                  o.orderId.contains(_searchQuery); // 支援搜尋訂單號
              final matchesStatus = _showArchived
                  ? o.status == WorkshopStatus.archived
                  : o.status != WorkshopStatus.archived;
              final matchesFilter = _matchesFilter(o);
              return matchesQuery && matchesStatus && matchesFilter;
            }).toList();

            // 如果是封存模式，顯示簡單列表 (含搜尋 + 日期範圍篩選)
            if (_showArchived) {
              final archiveFiltered = filteredOrders.where((o) {
                if (_archiveDateRange == null) return true;
                final orderDate = o.createdAt ?? o.dueDate;
                return !orderDate.isBefore(_archiveDateRange!.start) &&
                    !orderDate.isAfter(_archiveDateRange!.end);
              }).toList();

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(color: Colors.black),
                            decoration: InputDecoration(
                              hintText: 'Search archived orders...',
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
                            onChanged: (val) => setState(
                              () => _searchQuery = val.toLowerCase(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final range = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                              initialDateRange: _archiveDateRange,
                            );
                            if (range != null) {
                              setState(() => _archiveDateRange = range);
                            }
                          },
                          icon: const Icon(Icons.date_range, size: 18),
                          label: Text(
                            _archiveDateRange == null
                                ? 'Date Range'
                                : '${DateFormat('MM/dd').format(_archiveDateRange!.start)}–${DateFormat('MM/dd').format(_archiveDateRange!.end)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (_archiveDateRange != null)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () =>
                                setState(() => _archiveDateRange = null),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${archiveFiltered.length} records',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: archiveFiltered.length,
                      itemBuilder: (context, index) {
                        final order = archiveFiltered[index];
                        return Card(
                          child: ListTile(
                            leading: const IconText(
                              Icons.check_circle,
                              color: Colors.grey,
                            ),
                            title: Text(
                              order.customer,
                              style: const TextStyle(
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                            subtitle: Text(
                              '${order.item} #${order.orderId}\n${DateFormat('yyyy-MM-dd').format(order.dueDate)}',
                            ),
                            isThreeLine: true,
                            trailing: IconButton(
                              icon: const IconText(Icons.unarchive),
                              onPressed: () => _toggleArchive(order, false),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
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
                          style: const TextStyle(color: Colors.black),
                          decoration: InputDecoration(
                            hintText: AppLocalizations.of(
                              context,
                            ).searchWorkshopHint,
                            hintStyle: TextStyle(color: Colors.grey[600]),
                            prefixIcon: const IconText(Icons.search),
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
                                    icon: const IconText(Icons.clear),
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
                        const SizedBox(height: 12),
                        // 快速篩選列 + 排序
                        Row(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _buildFilterChip(
                                      'all',
                                      'All',
                                      Icons.dashboard,
                                      Colors.blue,
                                    ),
                                    const SizedBox(width: 8),
                                    _buildFilterChip(
                                      'urgent',
                                      'Urgent',
                                      Icons.local_fire_department,
                                      Colors.red,
                                    ),
                                    const SizedBox(width: 8),
                                    _buildFilterChip(
                                      'overdue',
                                      'Overdue',
                                      Icons.warning_rounded,
                                      Colors.red.shade700,
                                    ),
                                    const SizedBox(width: 8),
                                    _buildFilterChip(
                                      'soon',
                                      'Due Soon',
                                      Icons.schedule,
                                      Colors.orange,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: Icon(
                                Icons.sort,
                                color: _sortMode != 'dueDate'
                                    ? Colors.blue
                                    : Colors.grey[600],
                              ),
                              tooltip: 'Sort by',
                              initialValue: _sortMode,
                              onSelected: (val) =>
                                  setState(() => _sortMode = val),
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'dueDate',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today,
                                        size: 16,
                                        color: _sortMode == 'dueDate'
                                            ? Colors.blue
                                            : Colors.grey,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Due Date',
                                        style: TextStyle(
                                          color: _sortMode == 'dueDate'
                                              ? Colors.blue
                                              : null,
                                          fontWeight: _sortMode == 'dueDate'
                                              ? FontWeight.bold
                                              : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'priority',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.local_fire_department,
                                        size: 16,
                                        color: _sortMode == 'priority'
                                            ? Colors.blue
                                            : Colors.grey,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Priority',
                                        style: TextStyle(
                                          color: _sortMode == 'priority'
                                              ? Colors.blue
                                              : null,
                                          fontWeight: _sortMode == 'priority'
                                              ? FontWeight.bold
                                              : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'customer',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.person_outline,
                                        size: 16,
                                        color: _sortMode == 'customer'
                                            ? Colors.blue
                                            : Colors.grey,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Customer Name',
                                        style: TextStyle(
                                          color: _sortMode == 'customer'
                                              ? Colors.blue
                                              : null,
                                          fontWeight: _sortMode == 'customer'
                                              ? FontWeight.bold
                                              : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const IconText(Icons.dashboard_customize, size: 28),
                            const SizedBox(width: 12),
                            Text(
                              AppLocalizations.of(context).productionFlow,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            Text(
                              '${filteredOrders.length} ${AppLocalizations.of(context).activeTasks}',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
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
                        final stageId = stage['id'] as WorkshopStatus;
                        final stageOrders = filteredOrders
                            .where((o) => o.status == stageId)
                            .toList();
                        final l10n = AppLocalizations.of(context);
                        String stageLabel;
                        switch (stageId) {
                          case WorkshopStatus.measuring:
                            stageLabel = l10n.statusMeasuring;
                            break;
                          case WorkshopStatus.cutting:
                            stageLabel = l10n.statusCutting;
                            break;
                          case WorkshopStatus.sewing:
                            stageLabel = l10n.statusSewing;
                            break;
                          case WorkshopStatus.finishing:
                            stageLabel = l10n.statusFinishing;
                            break;
                          case WorkshopStatus.completed:
                            stageLabel = l10n.statusCompleted;
                            break;
                          default:
                            stageLabel = stage['labelKey'] as String;
                        }
                        return _buildKanbanColumn(
                          stageId,
                          stageLabel,
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

  Widget _buildFilterChip(
    String mode,
    String label,
    IconData icon,
    Color color,
  ) {
    final isSelected = _filterMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _filterMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : Colors.grey.shade300),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey[700],
              ),
            ),
          ],
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
    // 逾期置頂 + 套用自訂欄位排序
    final now = DateTime.now();
    List<WorkshopOrder> displayOrders = List.from(orders);
    displayOrders.sort((a, b) {
      final aOv = now.isAfter(a.dueDate);
      final bOv = now.isAfter(b.dueDate);
      if (aOv != bOv) return aOv ? -1 : 1;
      switch (_sortMode) {
        case 'priority':
          if (a.priority != b.priority) return a.priority == 'urgent' ? -1 : 1;
          return a.dueDate.compareTo(b.dueDate);
        case 'customer':
          return a.customer.toLowerCase().compareTo(b.customer.toLowerCase());
        default:
          return a.dueDate.compareTo(b.dueDate);
      }
    });
    final customOrder = _columnOrder[stageId];
    if (customOrder != null && customOrder.isNotEmpty) {
      displayOrders = [
        for (final id in customOrder) ...displayOrders.where((o) => o.id == id),
        ...displayOrders.where((o) => !customOrder.contains(o.id)),
      ];
    }
    final overdueCount = displayOrders
        .where((o) => now.isAfter(o.dueDate))
        .length;

    return DragTarget<WorkshopOrder>(
      onWillAcceptWithDetails: (details) => details.data.status != stageId,
      onAcceptWithDetails: (details) =>
          _updateOrderStatus(details.data, stageId),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return Container(
          width: _kColumnWidth,
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
                    IconText(Icons.circle, size: 12, color: color[700]),
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
                        '${displayOrders.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                    if (overdueCount > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$overdueCount ⚠',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // 訂單列表
              Expanded(
                child: displayOrders.isEmpty
                    ? Center(
                        child: Text(
                          AppLocalizations.of(context).noTasks,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.all(12),
                        buildDefaultDragHandles: false,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            final ids = displayOrders.map((o) => o.id).toList();
                            if (newIndex > oldIndex) newIndex--;
                            final removed = ids.removeAt(oldIndex);
                            ids.insert(newIndex, removed);
                            _columnOrder[stageId] = ids;
                          });
                        },
                        itemCount: displayOrders.length,
                        itemBuilder: (context, index) {
                          final order = displayOrders[index];

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

                          final isSelected = _selectedOrderIds.contains(
                            order.id,
                          );
                          return Padding(
                            key: ValueKey(order.id),
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GestureDetector(
                              onLongPress: _isSelectionMode
                                  ? null
                                  : () => setState(() {
                                      _isSelectionMode = true;
                                      _selectedOrderIds.add(order.id);
                                    }),
                              onTap: _isSelectionMode
                                  ? () => setState(() {
                                      if (isSelected) {
                                        _selectedOrderIds.remove(order.id);
                                        if (_selectedOrderIds.isEmpty) {
                                          _isSelectionMode = false;
                                        }
                                      } else {
                                        _selectedOrderIds.add(order.id);
                                      }
                                    })
                                  : null,
                              child: Stack(
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (!_isSelectionMode)
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              top: 14,
                                              right: 4,
                                            ),
                                            child: Icon(
                                              Icons.drag_handle,
                                              size: 18,
                                              color: Colors.grey[350],
                                            ),
                                          ),
                                        ),
                                      Expanded(
                                        child: _isSelectionMode
                                            ? WorkshopCard(
                                                order: order,
                                                onTap: () {},
                                              )
                                            : Draggable<WorkshopOrder>(
                                                data: order,
                                                feedback: SizedBox(
                                                  width: 280,
                                                  child: Material(
                                                    elevation: 4,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    child: Opacity(
                                                      opacity: 0.9,
                                                      child: WorkshopCard(
                                                        order: order,
                                                        onTap: () {},
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                childWhenDragging: Opacity(
                                                  opacity: 0.3,
                                                  child: WorkshopCard(
                                                    order: order,
                                                    onTap: () {},
                                                  ),
                                                ),
                                                child: WorkshopCard(
                                                  order: order,
                                                  onTap: () =>
                                                      _showOrderDetails(
                                                        context,
                                                        order,
                                                      ),
                                                  onEdit: () =>
                                                      _showOrderDetails(
                                                        context,
                                                        order,
                                                        initialEditing: true,
                                                      ),
                                                  onNextStage:
                                                      nextStatus != null
                                                      ? () =>
                                                            _updateOrderStatus(
                                                              order,
                                                              nextStatus!,
                                                            )
                                                      : null,
                                                  onArchive:
                                                      order.status ==
                                                          WorkshopStatus
                                                              .completed
                                                      ? () => _toggleArchive(
                                                          order,
                                                          true,
                                                        )
                                                      : null,
                                                  onFabricToggle: () =>
                                                      _toggleFabricOrdered(
                                                        order,
                                                      ),
                                                  onPrint: () => PdfService()
                                                      .printWorkshopOrder(
                                                        context,
                                                        order,
                                                      ),
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                                  if (_isSelectionMode)
                                    Positioned.fill(
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 150,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? Colors.blue.withValues(
                                                  alpha: 0.15,
                                                )
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: isSelected
                                              ? Border.all(
                                                  color: Colors.blue,
                                                  width: 2,
                                                )
                                              : null,
                                        ),
                                        child: isSelected
                                            ? const Align(
                                                alignment: Alignment.topRight,
                                                child: Padding(
                                                  padding: EdgeInsets.all(8),
                                                  child: CircleAvatar(
                                                    radius: 10,
                                                    backgroundColor:
                                                        Colors.blue,
                                                    child: Icon(
                                                      Icons.check,
                                                      color: Colors.white,
                                                      size: 12,
                                                    ),
                                                  ),
                                                ),
                                              )
                                            : null,
                                      ),
                                    ),
                                ],
                              ),
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
    bool isEditing = initialEditing;

    // 預先載入布料圖片資訊（非同步，不阻塞 dialog 開啟）
    Future<List<Map<String, dynamic>>> fabricsFuture = Future.value([]);
    if (order.orderId.isNotEmpty) {
      fabricsFuture = _dbService
          .getOrderItems(order.orderId)
          .then((items) async {
            if (items.isEmpty) return <Map<String, dynamic>>[];
            final inventory = await _dbService.getInventory();
            final invMap = {for (final m in inventory) m.id: m};

            final result = <Map<String, dynamic>>[];
            for (final item in items) {
              final String? fid = item.fabricId;
              final mat = fid != null ? invMap[fid] : null;
              final String? imgUrl = mat?.imageUrl;
              if (item.service.isEmpty && fid == null) continue;
              result.add({
                'service': item.service.isNotEmpty
                    ? item.service
                    : (item.serviceName ?? ''),
                'fabricName': item.fabricName ?? mat?.name ?? fid ?? '',
                'imageUrl': imgUrl,
                'qty': item.quantity,
              });
            }
            return result;
          })
          .catchError((_) => <Map<String, dynamic>>[]);
    }

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
                                  isEditing
                                      ? AppLocalizations.of(
                                          context,
                                        ).editOrderTitle
                                      : AppLocalizations.of(context).jobDetails,
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
                                        '${AppLocalizations.of(context).ticketNumber}${order.orderId}',
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
                                icon: const IconText(Icons.close),
                                onPressed: () => Navigator.pop(context),
                              ),
                          ],
                        ),
                        const Divider(height: 32),

                        // === 工序進度條 + 快速跳轉 ===
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: order.progress / 100,
                            minHeight: 8,
                            backgroundColor: Colors.grey[200],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              order.status == WorkshopStatus.completed
                                  ? Colors.green
                                  : Theme.of(context).primaryColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (!isEditing)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children:
                                [
                                  WorkshopStatus.measuring,
                                  WorkshopStatus.cutting,
                                  WorkshopStatus.sewing,
                                  WorkshopStatus.finishing,
                                  WorkshopStatus.completed,
                                ].map((s) {
                                  final isActive = order.status == s;
                                  final isPast =
                                      _statusIndex(s) <
                                      _statusIndex(order.status);
                                  return GestureDetector(
                                    onTap: isActive
                                        ? null
                                        : () async {
                                            await _updateOrderStatus(order, s);
                                            if (context.mounted) {
                                              Navigator.pop(context);
                                            }
                                          },
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: isActive
                                                ? Theme.of(context).primaryColor
                                                : (isPast
                                                      ? Colors.green
                                                      : Colors.grey[200]),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            _statusIcon(s),
                                            size: 14,
                                            color: (isActive || isPast)
                                                ? Colors.white
                                                : Colors.grey[500],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          s.label,
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: isActive
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: isActive
                                                ? Theme.of(context).primaryColor
                                                : Colors.grey[500],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                          ),
                        const SizedBox(height: 16),

                        // === 1. 客戶名稱 (唯讀) ===
                        _buildLabel(AppLocalizations.of(context).customerLabel),
                        Text(
                          order.customer,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // === 2. 款式欄位 (Item Style) ===
                        _buildLabel(AppLocalizations.of(context).itemStyle),
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
                              prefixIcon: const IconText(
                                Icons.checkroom,
                                size: 20,
                              ),
                            ),
                          )
                        else
                          Text(
                            order.item,
                            style: const TextStyle(fontSize: 16),
                          ),
                        const SizedBox(height: 20),

                        // === 2b. 布料圖片區 (唯讀，非同步載入) ===
                        if (!isEditing)
                          FutureBuilder<List<Map<String, dynamic>>>(
                            future: fabricsFuture,
                            builder: (context, snap) {
                              if (snap.connectionState ==
                                  ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: LinearProgressIndicator(),
                                );
                              }
                              final fabrics = snap.data ?? [];
                              if (fabrics.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel(
                                    AppLocalizations.of(context).fabricItems,
                                  ),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: fabrics.map((f) {
                                      final imgUrl = f['imageUrl'] as String?;
                                      final name =
                                          f['fabricName'] as String? ?? '';
                                      final service =
                                          f['service'] as String? ?? '';
                                      final qty = f['qty'] as int? ?? 1;
                                      return Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          GestureDetector(
                                            onTap:
                                                imgUrl != null &&
                                                    imgUrl.isNotEmpty
                                                ? () => _showImageFullScreen(
                                                    context,
                                                    imgUrl,
                                                    name.isNotEmpty
                                                        ? name
                                                        : service,
                                                  )
                                                : null,
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child:
                                                  imgUrl != null &&
                                                      imgUrl.isNotEmpty
                                                  ? Image.network(
                                                      imgUrl,
                                                      width: 120,
                                                      height: 120,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (ctx, e, t) =>
                                                          _fabricPlaceholder(),
                                                    )
                                                  : _fabricPlaceholder(),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          SizedBox(
                                            width: 120,
                                            child: Text(
                                              name.isNotEmpty ? name : service,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            'x$qty',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[500],
                                            ),
                                          ),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 20),
                                ],
                              );
                            },
                          ),
                        _buildLabel(AppLocalizations.of(context).dueDateLabel),
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
                                IconText(
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
                                  const IconText(
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
                        _buildLabel(AppLocalizations.of(context).notesLabel),
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
                                  ? AppLocalizations.of(context).noNotes
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
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.7),
                                  ),
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
                                      debugPrint('Save Error: $e');
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
                              icon: IconText(
                                isEditing ? Icons.save : Icons.edit,
                              ),
                              label: Text(
                                isEditing
                                    ? AppLocalizations.of(context).saveChanges
                                    : AppLocalizations.of(
                                        context,
                                      ).editOrderTitle,
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

  int _statusIndex(WorkshopStatus s) {
    const stages = [
      WorkshopStatus.measuring,
      WorkshopStatus.cutting,
      WorkshopStatus.sewing,
      WorkshopStatus.finishing,
      WorkshopStatus.completed,
    ];
    return stages.indexOf(s);
  }

  IconData _statusIcon(WorkshopStatus s) {
    switch (s) {
      case WorkshopStatus.measuring:
        return Icons.straighten;
      case WorkshopStatus.cutting:
        return Icons.content_cut;
      case WorkshopStatus.sewing:
        return Icons.auto_fix_high;
      case WorkshopStatus.finishing:
        return Icons.dry_cleaning;
      case WorkshopStatus.completed:
        return Icons.check_circle;
      default:
        return Icons.circle;
    }
  }

  Future<void> _bulkAdvanceStage() async {
    final selectedOrders = _currentOrders
        .where((o) => _selectedOrderIds.contains(o.id))
        .toList();
    for (final order in selectedOrders) {
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
          break;
      }
      if (nextStatus != null) await _updateOrderStatus(order, nextStatus);
    }
    setState(() {
      _selectedOrderIds.clear();
      _isSelectionMode = false;
    });
  }

  void _showNewOrderDialog(BuildContext context) {
    final customerController = TextEditingController();
    final itemController = TextEditingController();
    String priority = 'normal';
    DateTime dueDate = DateTime.now().add(const Duration(days: 7));

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'New Workshop Order',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'CUSTOMER NAME',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: customerController,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: 'e.g. Chan Tai Man',
                            prefixIcon: const Icon(Icons.person_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'ITEM / DESCRIPTION',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: itemController,
                          decoration: InputDecoration(
                            hintText: 'e.g. 3-Piece Suit, VBC Fabric',
                            prefixIcon: const Icon(Icons.checkroom_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'PRIORITY',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setDialogState(() => priority = 'normal'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: priority == 'normal'
                                        ? Colors.blue
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: priority == 'normal'
                                          ? Colors.blue
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Normal',
                                      style: TextStyle(
                                        color: priority == 'normal'
                                            ? Colors.white
                                            : Colors.grey[700],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setDialogState(() => priority = 'urgent'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: priority == 'urgent'
                                        ? Colors.red
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: priority == 'urgent'
                                          ? Colors.red
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.local_fire_department,
                                        size: 16,
                                        color: priority == 'urgent'
                                            ? Colors.white
                                            : Colors.red,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Urgent',
                                        style: TextStyle(
                                          color: priority == 'urgent'
                                              ? Colors.white
                                              : Colors.red,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'DUE DATE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: dueDate,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365 * 2),
                              ),
                            );
                            if (picked != null) {
                              setDialogState(() => dueDate = picked);
                            }
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(8),
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
                                  DateFormat('yyyy-MM-dd').format(dueDate),
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const Spacer(),
                                const Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final customer = customerController.text.trim();
                                final item = itemController.text.trim();
                                if (customer.isEmpty || item.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please fill in customer name and item',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                Navigator.pop(context);
                                await _dbService.addWorkshopOrder(
                                  WorkshopOrder(
                                    id: '',
                                    customer: customer,
                                    item: item,
                                    priority: priority,
                                    status: WorkshopStatus.measuring,
                                    progress: 0,
                                    dueDate: dueDate,
                                    notes: '',
                                    createdAt: DateTime.now(),
                                    updatedAt: DateTime.now(),
                                  ),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Workshop order created'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Create Order'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
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

  void _showImageFullScreen(BuildContext context, String imgUrl, String label) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            // 可縮放圖片
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: Image.network(
                  imgUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                  errorBuilder: (_, e, t) => const IconText(
                    Icons.broken_image,
                    color: Colors.white54,
                    size: 64,
                  ),
                ),
              ),
            ),
            // 圖片名稱 + 關閉按鈕
            Positioned(
              top: 8,
              left: 12,
              right: 8,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const IconText(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fabricPlaceholder() {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconText(Icons.texture, size: 48, color: Colors.grey[400]),
    );
  }
}
