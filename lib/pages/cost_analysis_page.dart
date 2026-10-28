import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/order.dart';
import '../models/service_item.dart';
import '../services/database_service.dart';
import '../services/cost_calculation_service.dart';
import '../services/settings_service.dart';
import 'pos_page.dart';

// ─── Chart / data accent colours (intentional fixed values) ──────────────────
const Color _accentRevenue = Color(0xFF3B82F6);
const Color _accentProfit = Color(0xFF10B981);
const Color _accentCost = Color(0xFFEF4444);
const Color _accentMaterial = Color(0xFFF59E0B);
const Color _accentOutsource = Color(0xFF8B5CF6);
const Color _accentFixed = Color(0xFF6B7280);

final _fmtCurrency = NumberFormat('#,##0', 'zh_HK');
String _currencySymbol = 'HK\$';
String _fmtHKD(double v) => '$_currencySymbol ${_fmtCurrency.format(v.abs())}';

String _codeToSymbol(String code) => switch (code) {
  'USD' => 'US\$',
  'HKD' => 'HK\$',
  'TWD' => 'NT\$',
  'EUR' => '€',
  'GBP' => '£',
  _ => code,
};

// ─── Page ─────────────────────────────────────────────────────────────────────

class CostAnalysisPage extends StatefulWidget {
  const CostAnalysisPage({super.key});

  @override
  State<CostAnalysisPage> createState() => _CostAnalysisPageState();
}

class _CostAnalysisPageState extends State<CostAnalysisPage> {
  final DatabaseService _dbService = DatabaseService();
  String _timeFilter = 'Month';
  Map<String, ServiceItem> _serviceByName = {};

  String? _customerFilter;
  DateTimeRange? _customDateRange;
  final TextEditingController _customerSearchCtrl = TextEditingController();

  // Sort state for order breakdown
  String _sortBy = 'date'; // 'date' | 'margin' | 'revenue'
  bool _sortDesc = true;

  @override
  void initState() {
    super.initState();
    _dbService.getServicesStream().listen((services) {
      if (mounted) {
        setState(() {
          _serviceByName = {for (final s in services) s.name: s};
        });
      }
    });
    SettingsService().loadSettings().then((s) {
      final symbol = _codeToSymbol(s['currency'] as String? ?? 'HKD');
      if (mounted) setState(() => _currencySymbol = symbol);
    });
  }

  @override
  void dispose() {
    _customerSearchCtrl.dispose();
    super.dispose();
  }

  double _resolveOutsourcingCost(Order order) => order.outsourcingCost;
  double _resolveRevenue(Order order) => order.total;
  double _resolveTotalCost(Order order) {
    if (order.totalCost > 0) return order.totalCost;
    return CostCalculationService.calculateTotalCost(
      materialCost: order.materialCost,
      outsourcingCost: order.outsourcingCost,
      fixedCost: order.fixedCost,
      laborCost: order.laborCost,
    );
  }

  Future<void> _editOrderFromCostBreakdown(
    BuildContext ctx,
    Order order,
  ) async {
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final fetchedItems = await _dbService.getOrderItems(order.id);
      final Order fullOrder;
      if (fetchedItems.isNotEmpty) {
        final editItems = fetchedItems
            .map((item) => item.copyWith(manualUnitPrice: true))
            .toList();
        fullOrder = order.copyWith(items: editItems);
      } else {
        final serviceByName = _serviceByName.isNotEmpty
            ? _serviceByName
            : {
                for (final s in await _dbService.getServicesStream().first)
                  s.name: s,
              };
        fullOrder = CostCalculationService.syncOrderWithServicePrices(
          order.copyWith(items: order.items),
          serviceByName: serviceByName,
        );
      }
      if (!ctx.mounted) return;
      Navigator.pop(ctx);
      await Navigator.push(
        ctx,
        MaterialPageRoute(builder: (_) => POSPage(orderForEdit: fullOrder)),
      );
    } catch (e) {
      if (!ctx.mounted) return;
      Navigator.pop(ctx);
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('載入訂單失敗: $e'),
          backgroundColor: Theme.of(ctx).colorScheme.error,
        ),
      );
    }
  }

  List<Order> _filterOrdersByDate(List<Order> orders) {
    final now = DateTime.now();
    return orders.where((order) {
      if (order.createdAt == null) return false;
      final date = order.createdAt!;
      if (_customDateRange != null) {
        return !date.isBefore(_customDateRange!.start) &&
            !date.isAfter(
              _customDateRange!.end.add(const Duration(days: 1)),
            );
      }
      switch (_timeFilter) {
        case 'Week':
          return now.difference(date).inDays <= 7;
        case 'Month':
          return date.month == now.month && date.year == now.year;
        case 'Year':
          return date.year == now.year;
        default:
          return true;
      }
    }).toList();
  }

  // Orders from the period immediately before the current filter period
  List<Order> _filterOrdersByLastPeriod(List<Order> orders) {
    if (_customDateRange != null || _timeFilter == 'All') return [];
    final now = DateTime.now();
    return orders.where((order) {
      if (order.createdAt == null) return false;
      final date = order.createdAt!;
      switch (_timeFilter) {
        case 'Week':
          final diff = now.difference(date).inDays;
          return diff > 7 && diff <= 14;
        case 'Month':
          final lastMonth = DateTime(now.year, now.month - 1);
          return date.year == lastMonth.year && date.month == lastMonth.month;
        case 'Year':
          return date.year == now.year - 1;
        default:
          return false;
      }
    }).toList();
  }

  List<Order> _applyCustomerFilter(List<Order> orders) {
    if (_customerFilter == null || _customerFilter!.isEmpty) return orders;
    return orders
        .where(
          (o) => o.customerName.toLowerCase().contains(
            _customerFilter!.toLowerCase(),
          ),
        )
        .toList();
  }

  List<_MonthlyData> _buildMonthlyData(List<Order> all) {
    final now = DateTime.now();
    final result = <_MonthlyData>[];
    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final inMonth = all.where((o) {
        if (o.createdAt == null || o.status == 'cancelled') return false;
        return o.createdAt!.year == month.year &&
            o.createdAt!.month == month.month;
      }).toList();
      double rev = 0, cost = 0;
      for (final o in inMonth) {
        rev += _resolveRevenue(o);
        cost += _resolveTotalCost(o);
      }
      result.add(_MonthlyData(month, rev, cost, rev - cost));
    }
    return result;
  }

  String get _filterLabel {
    if (_customDateRange != null) {
      final f = DateFormat('MM/dd');
      return '${f.format(_customDateRange!.start)} – ${f.format(_customDateRange!.end)}';
    }
    switch (_timeFilter) {
      case 'Week':
        return '本週';
      case 'Month':
        return '本月';
      case 'Year':
        return '本年';
      default:
        return '全部';
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customDateRange,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(
            context,
          ).colorScheme.copyWith(primary: _accentRevenue),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _timeFilter = 'Custom';
      });
    }
  }

  void _showCustomerFilterDialog() {
    _customerSearchCtrl.text = _customerFilter ?? '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('客戶篩選'),
        content: TextField(
          controller: _customerSearchCtrl,
          decoration: const InputDecoration(
            hintText: '輸入客戶名稱（模糊搜尋）',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _customerFilter = null);
              _customerSearchCtrl.clear();
              Navigator.pop(ctx);
            },
            child: const Text('清除'),
          ),
          FilledButton(
            onPressed: () {
              setState(
                () => _customerFilter =
                    _customerSearchCtrl.text.trim().isEmpty
                    ? null
                    : _customerSearchCtrl.text.trim(),
              );
              Navigator.pop(ctx);
            },
            child: const Text('確認'),
          ),
        ],
      ),
    );
  }

  // % change vs last period; null when last == 0
  double? _trendPct(double current, double last) {
    if (last == 0) return null;
    return (current - last) / last.abs() * 100;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Cost & Profit',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: cs.outlineVariant),
        ),
        actions: const [],
      ),
      body: Builder(
        builder: (scaffoldCtx) => StreamBuilder<List<Order>>(
          stream: _dbService.getOrdersStream(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final allOrders = snapshot.data!;
            final dateFiltered = _filterOrdersByDate(allOrders);
            final filteredOrders = _applyCustomerFilter(dateFiltered);
            final monthlyData = _buildMonthlyData(allOrders);

            // Current period metrics
            double totalRevenue = 0, totalMaterialCost = 0;
            double totalOutsourcingCost = 0, totalFixedCost = 0, totalCost = 0;
            int orderCount = 0, lossCount = 0;
            double totalLoss = 0;

            for (final o in filteredOrders) {
              if (o.status == 'cancelled') continue;
              orderCount++;
              final rev = _resolveRevenue(o);
              final cost = _resolveTotalCost(o);
              totalRevenue += rev;
              totalMaterialCost += o.materialCost;
              totalOutsourcingCost += _resolveOutsourcingCost(o);
              totalFixedCost += o.fixedCost;
              totalCost += cost;
              if (rev - cost < 0) {
                lossCount++;
                totalLoss += cost - rev;
              }
            }

            final totalProfit = totalRevenue - totalCost;
            final margin = totalRevenue > 0
                ? (totalProfit / totalRevenue) * 100
                : 0.0;
            final avgOrderValue =
                orderCount > 0 ? totalRevenue / orderCount : 0.0;

            // Last period metrics for trend comparison
            final lastPeriodOrders = _applyCustomerFilter(
              _filterOrdersByLastPeriod(allOrders),
            ).where((o) => o.status != 'cancelled').toList();

            double lastRevenue = 0, lastCost = 0, lastMaterial = 0;
            double lastOutsource = 0, lastFixed = 0;
            int lastCount = 0;
            for (final o in lastPeriodOrders) {
              lastRevenue += _resolveRevenue(o);
              lastCost += _resolveTotalCost(o);
              lastMaterial += o.materialCost;
              lastOutsource += _resolveOutsourcingCost(o);
              lastFixed += o.fixedCost;
              lastCount++;
            }
            final lastProfit = lastRevenue - lastCost;
            final lastMargin =
                lastRevenue > 0 ? (lastProfit / lastRevenue) * 100 : 0.0;
            final lastAvg = lastCount > 0 ? lastRevenue / lastCount : 0.0;
            final hasTrend = lastPeriodOrders.isNotEmpty;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FilterBar(
                    timeFilter: _timeFilter,
                    customDateRange: _customDateRange,
                    customerFilter: _customerFilter,
                    onTimeFilterChanged: (val) => setState(() {
                      _timeFilter = val;
                      _customDateRange = null;
                    }),
                    onPickDateRange: _pickDateRange,
                    onSearchCustomer: _showCustomerFilterDialog,
                    onClearCustomer: () =>
                        setState(() => _customerFilter = null),
                    onClearDate: () => setState(() {
                      _customDateRange = null;
                      _timeFilter = 'Month';
                    }),
                  ),
                  const SizedBox(height: 16),
                  _SectionHeader(
                    label: '概覽  ·  $_filterLabel',
                    sub: '$orderCount 張訂單',
                  ),
                  const SizedBox(height: 12),
                  _KpiGrid(
                    revenue: totalRevenue,
                    profit: totalProfit,
                    cost: totalCost,
                    margin: margin,
                    materialCost: totalMaterialCost,
                    outsourceCost: totalOutsourcingCost,
                    fixedCost: totalFixedCost,
                    avgOrderValue: avgOrderValue,
                    revenueTrend:
                        hasTrend ? _trendPct(totalRevenue, lastRevenue) : null,
                    profitTrend:
                        hasTrend ? _trendPct(totalProfit, lastProfit) : null,
                    costTrend:
                        hasTrend ? _trendPct(totalCost, lastCost) : null,
                    marginTrend: hasTrend ? (margin - lastMargin) : null,
                    materialTrend:
                        hasTrend
                        ? _trendPct(totalMaterialCost, lastMaterial)
                        : null,
                    outsourceTrend:
                        hasTrend
                        ? _trendPct(totalOutsourcingCost, lastOutsource)
                        : null,
                    fixedTrend:
                        hasTrend ? _trendPct(totalFixedCost, lastFixed) : null,
                    avgTrend:
                        hasTrend ? _trendPct(avgOrderValue, lastAvg) : null,
                  ),
                  if (lossCount > 0) ...[
                    const SizedBox(height: 12),
                    _LossAlert(lossCount: lossCount, totalLoss: totalLoss),
                  ],
                  const SizedBox(height: 28),
                  const _SectionHeader(label: '6 個月趨勢'),
                  const SizedBox(height: 12),
                  _TrendChart(data: monthlyData),
                  const SizedBox(height: 28),
                  const _SectionHeader(label: '成本組成'),
                  const SizedBox(height: 12),
                  _CostCompositionCard(
                    totalMaterialCost: totalMaterialCost,
                    totalOutsourcingCost: totalOutsourcingCost,
                    totalFixedCost: totalFixedCost,
                  ),
                  const SizedBox(height: 28),
                  _SectionHeader(
                    label: '訂單明細',
                    sub: (_customerFilter != null &&
                            _customerFilter!.isNotEmpty)
                        ? '篩選: $_customerFilter'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  _SortBar(
                    sortBy: _sortBy,
                    sortDesc: _sortDesc,
                    onSort: (by, desc) =>
                        setState(() {
                          _sortBy = by;
                          _sortDesc = desc;
                        }),
                  ),
                  const SizedBox(height: 8),
                  _OrderBreakdownList(
                    orders: filteredOrders,
                    sortBy: _sortBy,
                    sortDesc: _sortDesc,
                    resolveRevenue: _resolveRevenue,
                    resolveOutsourcing: _resolveOutsourcingCost,
                    resolveTotalCost: _resolveTotalCost,
                    onTap: (o) => _showCostDetailDialog(scaffoldCtx, o),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // 成本由系統按訂單細項計，呢度只顯示；要改成本請用「編輯訂單」改細項。
  void _showCostDetailDialog(BuildContext context, Order order) {
    showDialog(
      context: context,
      builder: (ctx) => Builder(
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          final dialogRevenue = order.total;
          final materialCost = order.materialCost;
          final outsourcingCost = order.outsourcingCost;
          final dialogTotalCost = order.totalCost > 0
              ? order.totalCost
              : CostCalculationService.calculateTotalCost(
                  materialCost: order.materialCost,
                  outsourcingCost: order.outsourcingCost,
                  fixedCost: order.fixedCost,
                  laborCost: order.laborCost,
                );
          final dialogProfit = dialogRevenue - dialogTotalCost;
          final marginPct = dialogRevenue > 0
              ? (dialogProfit / dialogRevenue * 100)
              : 0.0;
          final isProfitable = dialogProfit >= 0;

          Color statusColor;
          String statusLabel;
          switch (order.status) {
            case 'completed':
              statusColor = _accentProfit;
              statusLabel = '已完成';
            case 'cancelled':
              statusColor = _accentCost;
              statusLabel = '已取消';
            case 'in_progress':
              statusColor = _accentRevenue;
              statusLabel = '進行中';
            default:
              statusColor = _accentMaterial;
              statusLabel = '待處理';
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 32,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 40,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header — intentional dark banner
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1E293B),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.receipt_long_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  order.customerName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  '#${order.id.length >= 6 ? order.id.substring(0, 6).toUpperCase() : order.id.toUpperCase()}  ·  ${DateFormat('yyyy-MM-dd').format(order.createdAt ?? order.date ?? DateTime.now())}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: statusColor.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white54,
                              size: 20,
                            ),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    // Body
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: LayoutBuilder(
                          builder: (_, constraints) {
                            final wide = constraints.maxWidth > 500;
                            final left = _buildDialogLeft(
                              ctx,
                              order,
                              dialogRevenue,
                              dialogProfit,
                              marginPct,
                              isProfitable,
                              dialogTotalCost,
                              materialCost,
                              outsourcingCost,
                            );
                            final right = _buildDialogRight(
                              ctx,
                              order,
                              dialogRevenue,
                              dialogProfit,
                              materialCost,
                              outsourcingCost,
                              isProfitable,
                              dialogTotalCost,
                            );
                            if (wide) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 5, child: left),
                                  const SizedBox(width: 20),
                                  Expanded(flex: 6, child: right),
                                ],
                              );
                            }
                            return Column(
                              children: [
                                left,
                                const SizedBox(height: 20),
                                right,
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    // Footer
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: cs.outlineVariant),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _editOrderFromCostBreakdown(context, order);
                            },
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('編輯訂單'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDialogLeft(
    BuildContext context,
    Order order,
    double revenue,
    double profit,
    double marginPct,
    bool isProfitable,
    double totalCost,
    double materialCost,
    double outsourcingCost,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: (isProfitable ? _accentProfit : _accentCost).withValues(
              alpha: 0.06,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: (isProfitable ? _accentProfit : _accentCost).withValues(
                alpha: 0.2,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '淨利潤',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _fmtHKD(profit),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: isProfitable ? _accentProfit : _accentCost,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isProfitable ? _accentProfit : _accentCost)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '利潤率 ${marginPct.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isProfitable ? _accentProfit : _accentCost,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _InfoTile(
          label: '總收入',
          value: _fmtHKD(revenue),
          icon: Icons.arrow_upward_rounded,
          color: _accentRevenue,
        ),
        const SizedBox(height: 8),
        _InfoTile(
          label: '總成本',
          value: _fmtHKD(totalCost),
          icon: Icons.arrow_downward_rounded,
          color: _accentCost,
        ),
        const SizedBox(height: 8),
        _InfoTile(
          label: '付款方式',
          value: order.paymentMethod,
          icon: Icons.credit_card_outlined,
          color: cs.outline,
        ),
        if (order.deliveryDate != null) ...[
          const SizedBox(height: 8),
          _InfoTile(
            label: '交貨日期',
            value: DateFormat('yyyy-MM-dd').format(order.deliveryDate!),
            icon: Icons.event_outlined,
            color: cs.outline,
          ),
        ],
        if (order.itemSummary.isNotEmpty) ...[
          const SizedBox(height: 8),
          _InfoTile(
            label: '項目',
            value: order.itemSummary,
            icon: Icons.list_alt_outlined,
            color: cs.outline,
          ),
        ],
      ],
    );
  }

  Widget _buildDialogRight(
    BuildContext context,
    Order order,
    double revenue,
    double profit,
    double materialCost,
    double outsourcingCost,
    bool isProfitable,
    double totalCost,
  ) {
    final cs = Theme.of(context).colorScheme;
    final knownCost = materialCost + outsourcingCost + order.fixedCost;
    final otherCost = totalCost - knownCost;
    final showOther = otherCost.abs() > 0.01;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '成本明細',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            children: [
              _BreakdownRow(
                label: '總收入',
                amount: revenue,
                color: _accentRevenue,
                bold: true,
              ),
              Divider(height: 16, color: cs.outlineVariant),
              _BreakdownRow(
                label: '物料成本',
                amount: -materialCost,
                color: _accentMaterial,
                sub: '布料 / 材料',
              ),
              const SizedBox(height: 6),
              _BreakdownRow(
                label: '外包成本',
                amount: -outsourcingCost,
                color: _accentOutsource,
                sub: '外部供應商',
              ),
              const SizedBox(height: 6),
              _BreakdownRow(
                label: '固定成本',
                amount: -order.fixedCost,
                color: _accentFixed,
                sub: '分攤管理費',
              ),
              if (showOther) ...[
                const SizedBox(height: 6),
                _BreakdownRow(
                  label: '其他成本',
                  amount: -otherCost,
                  color: cs.outline,
                  sub: '工資 / 其他',
                ),
              ],
              Divider(height: 16, color: cs.outlineVariant),
              _BreakdownRow(
                label: '淨利潤',
                amount: profit,
                color: isProfitable ? _accentProfit : _accentCost,
                bold: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Dialog helper widgets ─────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.amount,
    required this.color,
    this.sub,
    this.bold = false,
  });
  final String label;
  final double amount;
  final Color color;
  final String? sub;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 4,
          height: bold ? 28 : 22,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: bold ? 13 : 12,
                  fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
              if (sub != null)
                Text(
                  sub!,
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ),
        Text(
          '${amount < 0 ? '−' : '+'}${_fmtHKD(amount)}',
          style: TextStyle(
            fontSize: bold ? 14 : 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ─── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.sub});
  final String label;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
        if (sub != null) ...[
          const SizedBox(width: 8),
          Text(
            sub!,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

// ─── Sort bar ─────────────────────────────────────────────────────────────────

class _SortBar extends StatelessWidget {
  const _SortBar({
    required this.sortBy,
    required this.sortDesc,
    required this.onSort,
  });
  final String sortBy;
  final bool sortDesc;
  final void Function(String by, bool desc) onSort;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const options = [('date', '日期'), ('margin', '利潤率'), ('revenue', '收入')];
    return Row(
      children: [
        Text(
          '排序：',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        const SizedBox(width: 6),
        ...options.map((opt) {
          final (id, label) = opt;
          final selected = sortBy == id;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () =>
                  selected ? onSort(id, !sortDesc) : onSort(id, true),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? cs.primaryContainer
                      : cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected ? cs.primary : cs.outlineVariant,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        color: selected
                            ? cs.onPrimaryContainer
                            : cs.onSurfaceVariant,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: 3),
                      Icon(
                        sortDesc
                            ? Icons.arrow_downward
                            : Icons.arrow_upward,
                        size: 11,
                        color: cs.onPrimaryContainer,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

// ─── Loss alert banner ────────────────────────────────────────────────────────

class _LossAlert extends StatelessWidget {
  const _LossAlert({required this.lossCount, required this.totalLoss});
  final int lossCount;
  final double totalLoss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: cs.onErrorContainer,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$lossCount 筆訂單虧損',
              style: TextStyle(
                color: cs.onErrorContainer,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            '合計虧損 ${_fmtHKD(totalLoss)}',
            style: TextStyle(
              color: cs.onErrorContainer,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Filter bar ───────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.timeFilter,
    required this.customDateRange,
    required this.customerFilter,
    required this.onTimeFilterChanged,
    required this.onPickDateRange,
    required this.onSearchCustomer,
    required this.onClearCustomer,
    required this.onClearDate,
  });

  final String timeFilter;
  final DateTimeRange? customDateRange;
  final String? customerFilter;
  final ValueChanged<String> onTimeFilterChanged;
  final VoidCallback onPickDateRange;
  final VoidCallback onSearchCustomer;
  final VoidCallback onClearCustomer;
  final VoidCallback onClearDate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat('MM/dd');
    final bool hasDateFilter = customDateRange != null;
    final bool hasCustomerFilter =
        customerFilter != null && customerFilter!.isNotEmpty;

    const periods = [
      ('Week', '本週'),
      ('Month', '本月'),
      ('Year', '本年'),
      ('All', '全部'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.filter_list_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                '篩選：',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: periods.map((p) {
                      final isSelected = !hasDateFilter && timeFilter == p.$1;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(p.$2),
                          selected: isSelected,
                          onSelected: (_) => onTimeFilterChanged(p.$1),
                          selectedColor: _accentRevenue.withValues(alpha: 0.15),
                          labelStyle: TextStyle(
                            color: isSelected ? _accentRevenue : cs.onSurface,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            fontSize: 13,
                          ),
                          side: BorderSide(
                            color: isSelected
                                ? _accentRevenue
                                : cs.outlineVariant,
                          ),
                          showCheckmark: false,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onPickDateRange,
                icon: Icon(
                  Icons.date_range_outlined,
                  size: 16,
                  color: hasDateFilter ? _accentRevenue : cs.onSurfaceVariant,
                ),
                label: Text(
                  hasDateFilter
                      ? '${fmt.format(customDateRange!.start)} – ${fmt.format(customDateRange!.end)}'
                      : '日期範圍',
                  style: TextStyle(
                    fontSize: 13,
                    color: hasDateFilter ? _accentRevenue : cs.onSurface,
                    fontWeight: hasDateFilter
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  side: BorderSide(
                    color: hasDateFilter ? _accentRevenue : cs.outlineVariant,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onSearchCustomer,
                icon: Icon(
                  Icons.person_search_outlined,
                  size: 16,
                  color: hasCustomerFilter
                      ? _accentRevenue
                      : cs.onSurfaceVariant,
                ),
                label: Text(
                  hasCustomerFilter ? customerFilter! : '客戶',
                  style: TextStyle(
                    fontSize: 13,
                    color: hasCustomerFilter ? _accentRevenue : cs.onSurface,
                    fontWeight: hasCustomerFilter
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  side: BorderSide(
                    color: hasCustomerFilter
                        ? _accentRevenue
                        : cs.outlineVariant,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              if (hasDateFilter)
                IconButton(
                  icon: Icon(Icons.close, size: 16, color: cs.onSurfaceVariant),
                  tooltip: '清除日期',
                  onPressed: onClearDate,
                ),
              if (hasCustomerFilter)
                IconButton(
                  icon: Icon(Icons.close, size: 16, color: cs.onSurfaceVariant),
                  tooltip: '清除客戶',
                  onPressed: onClearCustomer,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── KPI grid ─────────────────────────────────────────────────────────────────

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({
    required this.revenue,
    required this.profit,
    required this.cost,
    required this.margin,
    required this.materialCost,
    required this.outsourceCost,
    required this.fixedCost,
    required this.avgOrderValue,
    this.revenueTrend,
    this.profitTrend,
    this.costTrend,
    this.marginTrend,
    this.materialTrend,
    this.outsourceTrend,
    this.fixedTrend,
    this.avgTrend,
  });

  final double revenue, profit, cost, margin;
  final double materialCost, outsourceCost, fixedCost, avgOrderValue;
  final double? revenueTrend, profitTrend, costTrend, marginTrend;
  final double? materialTrend, outsourceTrend, fixedTrend, avgTrend;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _KpiCardData(
        '總收入',
        _fmtHKD(revenue),
        Icons.arrow_upward_rounded,
        _accentRevenue,
        '銷售總額',
        trend: revenueTrend,
      ),
      _KpiCardData(
        '淨利潤',
        _fmtHKD(profit),
        Icons.account_balance_wallet,
        profit >= 0 ? _accentProfit : _accentCost,
        '收入 − 成本',
        trend: profitTrend,
      ),
      _KpiCardData(
        '總成本',
        _fmtHKD(cost),
        Icons.arrow_downward_rounded,
        _accentCost,
        '實際總支出',
        trend: costTrend,
      ),
      _KpiCardData(
        '利潤率',
        '${margin.toStringAsFixed(1)}%',
        Icons.pie_chart,
        _accentProfit,
        '盈利能力',
        trend: marginTrend,
        isMarginalTrend: true,
      ),
      _KpiCardData(
        '物料成本',
        _fmtHKD(materialCost),
        Icons.texture,
        _accentMaterial,
        '布料 / 材料',
        trend: materialTrend,
      ),
      _KpiCardData(
        '外包成本',
        _fmtHKD(outsourceCost),
        Icons.handshake_outlined,
        _accentOutsource,
        '外部供應商',
        trend: outsourceTrend,
      ),
      _KpiCardData(
        '固定成本',
        _fmtHKD(fixedCost),
        Icons.apartment_outlined,
        _accentFixed,
        '分攤管理費',
        trend: fixedTrend,
      ),
      _KpiCardData(
        '平均客單價',
        _fmtHKD(avgOrderValue),
        Icons.shopping_bag_outlined,
        _accentRevenue,
        '每張訂單平均',
        trend: avgTrend,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 800 ? 4 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
          ),
          itemCount: cards.length,
          itemBuilder: (_, i) => _KpiCard(data: cards[i]),
        );
      },
    );
  }
}

class _KpiCardData {
  const _KpiCardData(
    this.title,
    this.value,
    this.icon,
    this.color,
    this.sub, {
    this.trend,
    this.isMarginalTrend = false,
  });
  final String title, value, sub;
  final IconData icon;
  final Color color;
  final double? trend; // % change vs last period (or pp for margin)
  final bool isMarginalTrend; // true → show as "pp" absolute points
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data});
  final _KpiCardData data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final trend = data.trend;
    final trendUp = trend != null && trend > 0;
    final trendDown = trend != null && trend < 0;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(data.icon, size: 16, color: data.color),
              ),
              const Spacer(),
              Text(
                data.sub,
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.title,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  data.value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: data.color,
                  ),
                ),
              ),
              if (trend != null) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      trendUp
                          ? Icons.trending_up
                          : trendDown
                          ? Icons.trending_down
                          : Icons.trending_flat,
                      size: 11,
                      color: trendUp
                          ? _accentProfit
                          : trendDown
                          ? _accentCost
                          : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      data.isMarginalTrend
                          ? '${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(1)} pp'
                          : '${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 10,
                        color: trendUp
                            ? _accentProfit
                            : trendDown
                            ? _accentCost
                            : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Trend chart ──────────────────────────────────────────────────────────────

class _MonthlyData {
  const _MonthlyData(this.month, this.revenue, this.cost, this.profit);
  final DateTime month;
  final double revenue, cost, profit;
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.data});
  final List<_MonthlyData> data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (data.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            '暫無數據',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    final maxY = data.fold<double>(0, (m, d) => m < d.revenue ? d.revenue : m);
    final topY = maxY <= 0 ? 1000.0 : (maxY * 1.2).ceilToDouble();

    final revenueSpots = <FlSpot>[];
    final costSpots = <FlSpot>[];
    final profitSpots = <FlSpot>[];
    for (int i = 0; i < data.length; i++) {
      revenueSpots.add(FlSpot(i.toDouble(), data[i].revenue));
      costSpots.add(FlSpot(i.toDouble(), data[i].cost));
      profitSpots.add(FlSpot(i.toDouble(), data[i].profit));
    }

    return Container(
      height: 230,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            children: [
              _LegendDot('收入', _accentRevenue),
              _LegendDot('成本', _accentCost),
              _LegendDot('利潤', _accentProfit),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: topY,
                clipData: const FlClipData.all(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= data.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            DateFormat('MM月').format(data[idx].month),
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  _lineBar(revenueSpots, _accentRevenue),
                  _lineBar(costSpots, _accentCost),
                  _lineBar(profitSpots, _accentProfit, dashed: true),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => cs.inverseSurface,
                    getTooltipItems: (spots) => spots
                        .map(
                          (s) => LineTooltipItem(
                            _fmtHKD(s.y),
                            TextStyle(
                              color: cs.onInverseSurface,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  LineChartBarData _lineBar(
    List<FlSpot> spots,
    Color color, {
    bool dashed = false,
  }) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 2.5,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: !dashed,
        color: color.withValues(alpha: 0.06),
      ),
      dashArray: dashed ? [4, 4] : null,
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ─── Cost composition pie ─────────────────────────────────────────────────────

class _CostCompositionCard extends StatelessWidget {
  const _CostCompositionCard({
    required this.totalMaterialCost,
    required this.totalOutsourcingCost,
    required this.totalFixedCost,
  });
  final double totalMaterialCost, totalOutsourcingCost, totalFixedCost;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sections = [
      _CostSlice('物料', totalMaterialCost, _accentMaterial),
      _CostSlice('外包', totalOutsourcingCost, _accentOutsource),
      _CostSlice('固定', totalFixedCost, _accentFixed),
    ].where((s) => s.value > 0).toList();

    final total = sections.fold<double>(0, (s, d) => s + d.value);

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: total <= 0
          ? SizedBox(
              height: 100,
              child: Center(
                child: Text(
                  '所選期間無成本記錄',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 600;
                final chart = SizedBox(
                  height: 200,
                  width: 200,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 48,
                      pieTouchData: PieTouchData(enabled: false),
                      sections: sections
                          .map(
                            (s) => PieChartSectionData(
                              value: s.value,
                              color: s.color,
                              radius: 52,
                              title:
                                  '${((s.value / total) * 100).toStringAsFixed(0)}%',
                              titleStyle: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                );

                final legend = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '總成本: ${_fmtHKD(total)}',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...sections.map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: s.color,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                s.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                            Text(
                              '${((s.value / total) * 100).toStringAsFixed(1)}%  ·  ${_fmtHKD(s.value)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      chart,
                      const SizedBox(width: 28),
                      Expanded(child: legend),
                    ],
                  );
                }
                return Column(
                  children: [chart, const SizedBox(height: 20), legend],
                );
              },
            ),
    );
  }
}

class _CostSlice {
  const _CostSlice(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
}

// ─── Order breakdown list ─────────────────────────────────────────────────────

class _OrderBreakdownList extends StatelessWidget {
  const _OrderBreakdownList({
    required this.orders,
    required this.sortBy,
    required this.sortDesc,
    required this.resolveRevenue,
    required this.resolveOutsourcing,
    required this.resolveTotalCost,
    required this.onTap,
  });

  final List<Order> orders;
  final String sortBy;
  final bool sortDesc;
  final double Function(Order) resolveRevenue;
  final double Function(Order) resolveOutsourcing;
  final double Function(Order) resolveTotalCost;
  final void Function(Order) onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = orders.where((o) => o.status != 'cancelled').toList();

    active.sort((a, b) {
      double valA, valB;
      switch (sortBy) {
        case 'margin':
          final revA = resolveRevenue(a), costA = resolveTotalCost(a);
          final revB = resolveRevenue(b), costB = resolveTotalCost(b);
          valA = revA > 0 ? ((revA - costA) / revA) : -999;
          valB = revB > 0 ? ((revB - costB) / revB) : -999;
        case 'revenue':
          valA = resolveRevenue(a);
          valB = resolveRevenue(b);
        default: // 'date'
          valA = (a.createdAt ?? DateTime(2000))
              .millisecondsSinceEpoch
              .toDouble();
          valB = (b.createdAt ?? DateTime(2000))
              .millisecondsSinceEpoch
              .toDouble();
      }
      return sortDesc ? valB.compareTo(valA) : valA.compareTo(valB);
    });

    if (active.isEmpty) {
      return Container(
        height: 80,
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Center(
          child: Text('暫無訂單', style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: active.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: cs.outlineVariant),
        itemBuilder: (_, i) {
          final order = active[i];
          final rev = resolveRevenue(order);
          final cost = resolveTotalCost(order);
          final profit = rev - cost;
          final isProfitable = profit >= 0;
          final marginPct = rev > 0 ? (profit / rev * 100) : 0.0;

          return InkWell(
            onTap: () => onTap(order),
            borderRadius: i == 0
                ? const BorderRadius.vertical(top: Radius.circular(16))
                : i == active.length - 1
                ? const BorderRadius.vertical(bottom: Radius.circular(16))
                : BorderRadius.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isProfitable ? _accentProfit : _accentCost,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.customerName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('yyyy-MM-dd').format(
                            order.createdAt ?? DateTime.now(),
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _fmtHKD(rev),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: _accentRevenue,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '利潤 ${_fmtHKD(profit)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isProfitable ? _accentProfit : _accentCost,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: (isProfitable
                                      ? _accentProfit
                                      : _accentCost)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${marginPct.toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 10,
                                color: isProfitable
                                    ? _accentProfit
                                    : _accentCost,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 18, color: cs.outlineVariant),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
