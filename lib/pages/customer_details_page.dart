import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../components/icon_text.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/contact_log.dart';
import '../models/customer.dart';
import '../models/order.dart';
import '../models/service_item.dart';
import '../services/database_service.dart';
import '../services/cost_calculation_service.dart';
import '../l10n/app_localizations.dart';
import 'pos_page.dart';

class _TimelineEntry {
  final bool isOrder;
  final ContactLog? contactLog;
  final Order? order;
  final DateTime date;

  _TimelineEntry.fromContact(ContactLog log)
      : isOrder = false,
        contactLog = log,
        order = null,
        date = log.createdAt;

  _TimelineEntry.fromOrder(Order o)
      : isOrder = true,
        contactLog = null,
        order = o,
        date = o.createdAt ?? o.date ?? DateTime(2000);
}

class CustomerDetailsPage extends StatefulWidget {
  final Customer customer;

  const CustomerDetailsPage({super.key, required this.customer});

  @override
  State<CustomerDetailsPage> createState() => _CustomerDetailsPageState();
}

class _CustomerDetailsPageState extends State<CustomerDetailsPage> {
  final DatabaseService _dbService = DatabaseService();
  late Customer _customer;
  StreamSubscription<Customer?>? _customerSubscription;
  String _timelineFilter = 'all';

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    _customerSubscription = _dbService
        .getCustomerStream(_customer.id)
        .listen((updated) {
      if (updated != null && mounted) {
        setState(() => _customer = updated);
      }
    });
  }

  @override
  void dispose() {
    _customerSubscription?.cancel();
    super.dispose();
  }

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch action')),
        );
      }
    }
  }

  void _showEditProfileDialog() {
    final nameController = TextEditingController(text: _customer.name);
    final phoneController = TextEditingController(text: _customer.phone);
    final emailController = TextEditingController(text: _customer.email);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).editCustomerProfile),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(ctx).nameLabel,
                  prefixIcon: const IconText(Icons.person),
                ),
                inputFormatters: [
                  TextInputFormatter.withFunction(
                    (oldValue, newValue) =>
                        newValue.copyWith(text: newValue.text.toUpperCase()),
                  ),
                ],
                validator: (v) =>
                    v!.isEmpty ? AppLocalizations.of(ctx).requiredField : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phoneController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(ctx).phoneLabel,
                  prefixIcon: const IconText(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: emailController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(ctx).emailLabel,
                  prefixIcon: const IconText(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx).cancelButton),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              final inputName = nameController.text.trim().toUpperCase();
              final inputPhone = phoneController.text.trim();
              final navigator = Navigator.of(ctx);
              final messenger = ScaffoldMessenger.of(context);
              final l10n = AppLocalizations.of(context);
              final cs = Theme.of(context).colorScheme;

              final existing = await _dbService.getCustomersStream().first;
              if (!mounted) return;

              final nameDup = existing.any(
                (c) => c.id != _customer.id && c.name.trim().toUpperCase() == inputName,
              );
              if (nameDup) {
                messenger.showSnackBar(SnackBar(
                  content: Text('客戶名稱「$inputName」已存在'),
                  backgroundColor: cs.error,
                ));
                return;
              }

              if (inputPhone.isNotEmpty) {
                final phoneDup = existing.any(
                  (c) => c.id != _customer.id && c.phone.trim() == inputPhone,
                );
                if (phoneDup) {
                  messenger.showSnackBar(SnackBar(
                    content: Text('電話號碼「$inputPhone」已有其他客戶登記'),
                    backgroundColor: cs.error,
                  ));
                  return;
                }
              }

              try {
                final updatedCustomer = _customer.copyWith(
                  name: inputName,
                  phone: inputPhone,
                  email: emailController.text.trim(),
                );
                await _dbService.updateCustomer(updatedCustomer);
                if (!mounted) return;
                setState(() => _customer = updatedCustomer);
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.profileUpdated)),
                );
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('${l10n.errorPrefix} $e')),
                  );
                }
              }
            },
            child: Text(AppLocalizations.of(ctx).saveButton),
          ),
        ],
      ),
    );
  }

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
        controllers[field] = TextEditingController(
          text: _customer.measurements[field] ?? '',
        );
      }

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.of(ctx).editMeasurements),
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
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(ctx).cancelButton),
            ),
            ElevatedButton(
              onPressed: () async {
                Map<String, String> newMeasurements = {};
                controllers.forEach((key, controller) {
                  if (controller.text.trim().isNotEmpty) {
                    newMeasurements[key] = controller.text.trim();
                  }
                });

                final navigator = Navigator.of(ctx);
                final messenger = ScaffoldMessenger.of(context);
                final l10n = AppLocalizations.of(context);

                try {
                  final updatedCustomer = _customer.copyWith(
                    measurements: newMeasurements,
                  );
                  await _dbService.updateCustomer(updatedCustomer);
                  if (!mounted) return;
                  setState(() => _customer = updatedCustomer);
                  navigator.pop();
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.measurementsUpdated)),
                  );
                } catch (e) {
                  debugPrint('Failed to update measurements: $e');
                }
              },
              child: Text(AppLocalizations.of(ctx).saveButton),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  void _showAddContactLogDialog() {
    String selectedType = 'note';
    final notesController = TextEditingController();
    DateTime? followUpDate;

    showDialog(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        final types = {
          'call': l10n.contactTypeCall,
          'fitting': l10n.contactTypeFitting,
          'message': l10n.contactTypeMessage,
          'note': l10n.contactTypeNote,
        };

        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(l10n.addContactLog),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.contactType,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: types.entries.map((e) {
                    final selected = selectedType == e.key;
                    return ChoiceChip(
                      label: Text(e.value),
                      selected: selected,
                      onSelected: (_) =>
                          setDialogState(() => selectedType = e.key),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notesController,
                  decoration: InputDecoration(
                    labelText: l10n.notesLabel,
                    hintText: l10n.notesHint,
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                // Follow-up date picker
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now().add(const Duration(days: 7)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setDialogState(() => followUpDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: l10n.followUpDate,
                      border: const OutlineInputBorder(),
                      suffixIcon: followUpDate != null
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () =>
                                  setDialogState(() => followUpDate = null),
                            )
                          : const Icon(Icons.event_outlined, size: 18),
                    ),
                    child: Text(
                      followUpDate != null
                          ? DateFormat('yyyy-MM-dd').format(followUpDate!)
                          : l10n.tapToSet,
                      style: TextStyle(
                        color: followUpDate != null
                            ? Theme.of(ctx).colorScheme.onSurface
                            : Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.cancelButton),
              ),
              ElevatedButton(
                onPressed: () async {
                  final notes = notesController.text.trim();
                  if (notes.isEmpty) return;
                  final navigator = Navigator.of(ctx);
                  final messenger = ScaffoldMessenger.of(context);
                  final outerL10n = AppLocalizations.of(context);
                  try {
                    await _dbService.addContactLog(
                      _customer.id,
                      ContactLog(
                        id: '',
                        type: selectedType,
                        notes: notes,
                        createdAt: DateTime.now(),
                        followUpDate: followUpDate,
                      ),
                    );
                    navigator.pop();
                    messenger.showSnackBar(
                      SnackBar(content: Text(outerL10n.contactLogAdded)),
                    );
                  } catch (e) {
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('${outerL10n.errorPrefix} $e')),
                      );
                    }
                  }
                },
                child: Text(l10n.saveButton),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.customerProfile),
        elevation: 0,
        actions: [
          IconButton(
            icon: const IconText(Icons.edit),
            tooltip: l10n.editProfileTooltip,
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
            _buildFollowUpBanner(),
            _buildOutstandingBalanceBanner(),
            const SizedBox(height: 24),

            // Body Measurements
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.bodyMeasurements,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton.icon(
                  onPressed: _showMeasurementsDialog,
                  icon: const IconText(Icons.straighten),
                  label: Text(l10n.editButton),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildMeasurementsGrid(),

            const SizedBox(height: 24),

            // Unified Timeline
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.timelineTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton.icon(
                  onPressed: _showAddContactLogDialog,
                  icon: const IconText(Icons.add),
                  label: Text(l10n.addContactLog),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildTimelineFilterChips(),
            const SizedBox(height: 12),
            _buildUnifiedTimeline(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    final cs = Theme.of(context).colorScheme;
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
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    _customer.name.isNotEmpty
                        ? _customer.name[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _customer.name,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildTierBadge(_customer.tier),
                        ],
                      ),
                      if (_customer.phone.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              IconText(
                                Icons.phone,
                                size: 16,
                                color: cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _customer.phone,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: cs.onSurface.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_customer.email.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _customer.email,
                            style: TextStyle(
                              fontSize: 14,
                              color: cs.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_customer.phone.isNotEmpty)
                  IconButton(
                    icon: IconText(Icons.call, color: cs.tertiary),
                    onPressed: () => _launchUrl('tel:${_customer.phone}'),
                  ),
              ],
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  AppLocalizations.of(context).totalSpent,
                  '\$${_customer.totalSpent.toStringAsFixed(0)}',
                  cs.tertiary,
                ),
                _buildStatItem(
                  AppLocalizations.of(context).ordersLabel,
                  '${_customer.orders}',
                  cs.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTierBadge(String tier) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final (label, bg, fg) = switch (tier) {
      'vip' => (l10n.tierVip, cs.primaryContainer, cs.onPrimaryContainer),
      'regular' => (l10n.tierRegular, cs.secondaryContainer, cs.onSecondaryContainer),
      _ => (l10n.tierNew, cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  Widget _buildFollowUpBanner() {
    final followUp = _customer.nextFollowUp;
    if (followUp == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(followUp.year, followUp.month, followUp.day);
    final isOverdue = dueDay.isBefore(today);
    final isToday = dueDay == today;

    final bg = isOverdue ? cs.errorContainer : cs.tertiaryContainer;
    final fg = isOverdue ? cs.onErrorContainer : cs.onTertiaryContainer;
    final icon = isOverdue ? Icons.warning_amber_rounded : Icons.notifications_outlined;
    final label = isOverdue
        ? '${l10n.followUpDue}: ${DateFormat('MM/dd').format(followUp)} ⚠️'
        : isToday
            ? '${l10n.followUpDue}: ${l10n.markDone.toLowerCase()} today'
            : '${l10n.followUpDate}: ${DateFormat('yyyy-MM-dd').format(followUp)}';

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () async {
              await _dbService.clearFollowUp(_customer.id);
            },
            style: TextButton.styleFrom(
              foregroundColor: fg,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(l10n.markDone),
          ),
        ],
      ),
    );
  }

  Widget _buildOutstandingBalanceBanner() {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<List<Order>>(
      stream: _dbService.getOrdersByCustomerIdStream(_customer.id),
      builder: (context, snapshot) {
        final orders = snapshot.data ?? [];
        final totalOutstanding = orders.fold<double>(
          0,
          (sum, o) => sum + (o.balance > 0 ? o.balance : 0),
        );
        if (totalOutstanding <= 0) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: cs.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  color: cs.onErrorContainer, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${l10n.outstandingBalance}: \$${totalOutstanding.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: cs.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildMeasurementsGrid() {
    final cs = Theme.of(context).colorScheme;
    if (_customer.measurements.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Center(
          child: Text(
            AppLocalizations.of(context).noMeasurements,
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
          ),
        ),
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
            color: cs.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                entry.key,
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
              Text(
                entry.value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTimelineFilterChips() {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final filters = [
      ('all', l10n.filterAll),
      ('contact', l10n.filterContact),
      ('fitting', l10n.filterFitting),
      ('order', l10n.filterOrder),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final selected = _timelineFilter == f.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(f.$2),
              selected: selected,
              onSelected: (_) => setState(() => _timelineFilter = f.$1),
              selectedColor: cs.primaryContainer,
              checkmarkColor: cs.onPrimaryContainer,
              labelStyle: TextStyle(
                color: selected ? cs.onPrimaryContainer : cs.onSurface,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildUnifiedTimeline() {
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<List<ServiceItem>>(
      stream: _dbService.getServicesStream(),
      builder: (context, serviceSnapshot) {
        final serviceByName = {
          for (final s in serviceSnapshot.data ?? <ServiceItem>[]) s.name: s,
        };
        return StreamBuilder<List<Order>>(
          stream: _dbService.getOrdersByCustomerIdStream(_customer.id),
          builder: (context, orderSnapshot) {
            return StreamBuilder<List<ContactLog>>(
              stream: _dbService.getContactLogsStream(_customer.id),
              builder: (context, logSnapshot) {
                if (orderSnapshot.connectionState == ConnectionState.waiting &&
                    logSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (orderSnapshot.hasError) {
                  return Text('${l10n.errorPrefix} ${orderSnapshot.error}');
                }

                final entries = <_TimelineEntry>[
                  ...(orderSnapshot.data ?? []).map(_TimelineEntry.fromOrder),
                  ...(logSnapshot.data ?? []).map(_TimelineEntry.fromContact),
                ];
                entries.sort((a, b) => b.date.compareTo(a.date));

                final filtered = switch (_timelineFilter) {
                  'order' => entries.where((e) => e.isOrder).toList(),
                  'fitting' => entries
                      .where((e) => !e.isOrder && e.contactLog!.type == 'fitting')
                      .toList(),
                  'contact' => entries
                      .where((e) => !e.isOrder && e.contactLog!.type != 'fitting')
                      .toList(),
                  _ => entries,
                };

                if (filtered.isEmpty) {
                  return _buildTimelineEmpty();
                }

                final widgets = <Widget>[];
                int? lastYear;
                for (int i = 0; i < filtered.length; i++) {
                  final entry = filtered[i];
                  if (entry.date.year != lastYear) {
                    widgets.add(_buildYearMarker(entry.date.year));
                    lastYear = entry.date.year;
                  }
                  widgets.add(_buildTimelineRow(
                    entry,
                    i == filtered.length - 1,
                    serviceByName,
                  ));
                }
                return Column(children: widgets);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildTimelineEmpty() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.timeline, size: 40, color: cs.onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context).noContactLogs,
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildYearMarker(int year) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const SizedBox(width: 48),
          SizedBox(
            width: 28,
            child: Center(
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.error,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$year',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: cs.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineRow(
    _TimelineEntry entry,
    bool isLast,
    Map<String, ServiceItem> serviceByName,
  ) {
    final cs = Theme.of(context).colorScheme;
    final day = DateFormat('d').format(entry.date);
    final mon = DateFormat('MMM').format(entry.date).toUpperCase();

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Date column
          SizedBox(
            width: 48,
            child: Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    day,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    mon,
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          // Line + dot
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 2,
                  height: 10,
                  color: cs.error.withValues(alpha: 0.4),
                ),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.error,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: cs.error.withValues(alpha: 0.2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Event card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: entry.isOrder
                  ? _buildTimelineOrderCard(entry.order!, serviceByName)
                  : _buildTimelineContactCard(entry.contactLog!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineContactCard(ContactLog log) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    final iconData = switch (log.type) {
      'call' => Icons.phone_outlined,
      'fitting' => Icons.straighten,
      'message' => Icons.message_outlined,
      _ => Icons.note_outlined,
    };
    final typeLabel = switch (log.type) {
      'call' => l10n.contactTypeCall,
      'fitting' => l10n.contactTypeFitting,
      'message' => l10n.contactTypeMessage,
      _ => l10n.contactTypeNote,
    };

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.secondaryContainer,
          child: IconText(iconData, color: cs.onSecondaryContainer, size: 20),
        ),
        title: Text(log.notes, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(typeLabel,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            if (log.followUpDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_outlined,
                          size: 11, color: cs.onTertiaryContainer),
                      const SizedBox(width: 3),
                      Text(
                        DateFormat('yyyy-MM-dd').format(log.followUpDate!),
                        style: TextStyle(
                            fontSize: 11, color: cs.onTertiaryContainer),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, color: cs.onSurfaceVariant, size: 20),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(l10n.deleteButton),
                content: Text(log.notes),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(l10n.cancelButton),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(
                      l10n.deleteButton,
                      style: TextStyle(color: cs.error),
                    ),
                  ),
                ],
              ),
            );
            if (ok == true && mounted) {
              await _dbService.deleteContactLog(_customer.id, log.id);
            }
          },
        ),
      ),
    );
  }

  Widget _buildTimelineOrderCard(
    Order order,
    Map<String, ServiceItem> serviceByName,
  ) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final summaryOrder = order.items.isNotEmpty
        ? CostCalculationService.syncOrderWithServicePrices(
            order,
            serviceByName: serviceByName,
          )
        : order;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: IconText(Icons.receipt_long, color: cs.onPrimaryContainer, size: 18),
        ),
        title: Text(
          'Order #${order.id}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: order.status != 'completed' && order.status != 'cancelled'
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _buildFabricOrderBadge(order.isFabricOrdered),
              )
            : null,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '\$${summaryOrder.total.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            _buildStatusBadge(order.status),
          ],
        ),
        children: [
          const Divider(height: 1),
          FutureBuilder<List<OrderItem>>(
            future: _dbService.getOrderItems(order.id),
            builder: (context, itemSnapshot) {
              if (itemSnapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final items = (itemSnapshot.data?.isNotEmpty == true)
                  ? itemSnapshot.data!
                  : order.items;
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No items details found'),
                );
              }
              final synced = CostCalculationService.syncOrderWithServicePrices(
                order.copyWith(items: items),
                serviceByName: serviceByName,
              );
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  children: [
                    ...synced.items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${item.service}${item.fabricName != null ? " (${item.fabricName})" : ""}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Text(
                              'x${item.quantity}',
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.6),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '\$${item.price.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: () {
                          final fullOrder = order.copyWith(items: items);
                          if (!mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (ctx) => POSPage(orderForEdit: fullOrder),
                            ),
                          );
                        },
                        icon: const Icon(Icons.edit_note, size: 16),
                        label: Text(
                          l10n.editOrderInPOS,
                          style: const TextStyle(fontSize: 13),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.primaryContainer,
                          foregroundColor: cs.onPrimaryContainer,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final cs = Theme.of(context).colorScheme;
    final color = switch (status) {
      'completed' => cs.tertiary,
      'confirmed' => cs.primary,
      'pending' => cs.secondary,
      'cancelled' => cs.error,
      _ => cs.onSurfaceVariant,
    };

    return Text(
      status.toUpperCase(),
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildFabricOrderBadge(bool isFabricOrdered) {
    final cs = Theme.of(context).colorScheme;
    final color = isFabricOrdered ? cs.tertiary : cs.error;
    final bgColor = isFabricOrdered ? cs.tertiaryContainer : cs.errorContainer;
    final borderColor =
        isFabricOrdered ? cs.tertiary.withValues(alpha: 0.4) : cs.error.withValues(alpha: 0.4);
    final icon = isFabricOrdered
        ? Icons.check_circle_outline
        : Icons.warning_amber_rounded;
    final label = isFabricOrdered ? 'Fabric Ordered' : 'Fabric Not Ordered';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconText(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
