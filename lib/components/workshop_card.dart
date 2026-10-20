import 'package:flutter/material.dart';
import 'icon_text.dart';
import 'package:intl/intl.dart';
import '../models/workshop_order.dart';
import '../models/workshop_status.dart';

class WorkshopCard extends StatelessWidget {
  final WorkshopOrder order;
  final VoidCallback onTap;
  final VoidCallback? onArchive;
  final VoidCallback? onEdit;
  final VoidCallback? onNextStage;
  final VoidCallback? onPrint;
  final VoidCallback? onFabricToggle;

  const WorkshopCard({
    super.key,
    required this.order,
    required this.onTap,
    this.onArchive,
    this.onEdit,
    this.onNextStage,
    this.onPrint,
    this.onFabricToggle,
  });

  @override
  Widget build(BuildContext context) {
    final bool isUrgent = order.priority == 'urgent';
    final bool isCompleted = order.status == WorkshopStatus.completed;
    final bool isArchived = order.status == WorkshopStatus.archived;
    final now = DateTime.now();
    final isOverdue = !isCompleted && !isArchived && now.isAfter(order.dueDate);
    final isDueSoon =
        !isCompleted &&
        !isArchived &&
        !isOverdue &&
        order.dueDate.difference(now).inDays <= 3;
    final daysLeft = order.dueDate.difference(now).inDays;

    // 顏色邏輯 (含到期日警示)
    Color cardColor;
    if (isArchived) {
      cardColor = Colors.grey;
    } else if (isCompleted) {
      cardColor = Colors.green;
    } else if (isUrgent || isOverdue) {
      cardColor = Colors.red;
    } else if (isDueSoon) {
      cardColor = Colors.orange;
    } else {
      cardColor = Colors.blue.shade600;
    }

    return Card(
      elevation: 2, // 降低一點陰影，看起來更現代扁平
      margin: const EdgeInsets.only(bottom: 12), // 縮小卡片間距
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias, // 確保左側顏色條不會溢出圓角
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: cardColor, width: 8), // 顏色條稍微改細一點，更精緻
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // === 1. 頂部：單號 + 狀態標籤 + 彈出選單 ===
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#${order.orderId}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // 縮小版的客人名稱
                        Text(
                          order.customer,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // 右上角區域：急件標籤 + 選單按鈕
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 急件標籤 (實色，更醒目)
                      if (isUrgent)
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconText(
                                Icons.local_fire_department,
                                size: 13,
                                color: Colors.white,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'URGENT',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // 逾期標籤 (非急件但已逾期)
                      if (!isUrgent && isOverdue)
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade700,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconText(
                                Icons.warning_rounded,
                                size: 13,
                                color: Colors.white,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'OVERDUE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // 即將到期標籤 (3 天內)
                      if (!isUrgent && !isOverdue && isDueSoon)
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const IconText(
                                Icons.schedule,
                                size: 13,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                daysLeft == 0 ? 'TODAY' : '${daysLeft}D LEFT',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // === 動作按鈕：直接顯示喺卡片上，唔使點隱藏式選單先搵到 ===
                      // 「下一階段」已經有底部嘅快速推進掣，呢度唔重複。
                      IconButton(
                        tooltip: 'Edit Details',
                        icon: const IconText(Icons.edit_outlined, size: 18),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(6),
                        onPressed: onEdit,
                      ),
                      if (onPrint != null)
                        IconButton(
                          tooltip: 'Print Job Ticket',
                          icon: const IconText(
                            Icons.print_outlined,
                            size: 18,
                          ),
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                          onPressed: onPrint,
                        ),
                      if (isCompleted && onArchive != null)
                        IconButton(
                          tooltip: 'Archive Order',
                          icon: IconText(
                            Icons.archive_outlined,
                            size: 18,
                            color: Colors.grey[700],
                          ),
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                          onPressed: onArchive,
                        ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // === 2. 中間：款式資訊 ===
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconText(
                      Icons.checkroom,
                      size: 18,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        order.item,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // === 3. 底部：交期 + 布料狀態 + 快速推進按鈕 ===
              Row(
                children: [
                  // 交期
                  IconText(
                    isOverdue ? Icons.warning_rounded : Icons.calendar_today,
                    size: 14,
                    color: isOverdue
                        ? Colors.red
                        : (isDueSoon ? Colors.orange : Colors.grey[600]),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('MMM dd').format(order.dueDate),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isOverdue
                          ? Colors.red
                          : (isDueSoon
                                ? Colors.orange[400]!
                                : Colors.grey[400]!),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 布料訂購狀態
                  GestureDetector(
                    onTap: onFabricToggle,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: order.isFabricOrdered
                            ? Colors.green.withValues(alpha: 0.12)
                            : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: order.isFabricOrdered
                              ? Colors.green.withValues(alpha: 0.4)
                              : Colors.grey.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.content_cut,
                            size: 11,
                            color: order.isFabricOrdered
                                ? Colors.green
                                : Colors.grey[500],
                          ),
                          const SizedBox(width: 3),
                          Text(
                            order.isFabricOrdered ? '已訂' : '未訂',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: order.isFabricOrdered
                                  ? Colors.green
                                  : Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  // 快速推進狀態按鈕
                  if (onNextStage != null && !isCompleted && !isArchived)
                    GestureDetector(
                      onTap: onNextStage,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: cardColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: cardColor.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              order.status.next?.label ?? '',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: cardColor,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(
                              Icons.arrow_forward,
                              size: 11,
                              color: cardColor,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Text(
                      order.status.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: cardColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),

            ],
          ),
        ),
      ),
    );
  }
}
