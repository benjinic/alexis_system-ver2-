import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/workshop_order.dart';
import '../models/workshop_status.dart';

class WorkshopCard extends StatelessWidget {
  final WorkshopOrder order;
  final VoidCallback onTap;
  final VoidCallback? onArchive;
  final VoidCallback? onEdit;
  final VoidCallback? onNextStage;
  final VoidCallback? onFabricToggle;

  const WorkshopCard({
    super.key,
    required this.order,
    required this.onTap,
    this.onArchive,
    this.onEdit,
    this.onNextStage,
    this.onFabricToggle,
  });

  @override
  Widget build(BuildContext context) {
    // 狀態判斷
    final bool isUrgent = order.priority == 'urgent';
    final bool isCompleted = order.status == WorkshopStatus.completed;

    // 顏色邏輯：急件=紅，完成=綠，一般=藍，封存=灰
    Color cardColor;
    if (order.status == WorkshopStatus.archived) {
      cardColor = Colors.grey;
    } else if (isCompleted) {
      cardColor = Colors.green;
    } else if (isUrgent) {
      cardColor = Colors.red;
    } else {
      cardColor = Colors.blue.shade700;
    }

    return Card(
      elevation: 4, // 增加陰影，更有立體感
      margin: const EdgeInsets.only(bottom: 16), // 卡片間距加大
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          // 加上左側顏色條 (Color Bar)
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border(
              left: BorderSide(color: cardColor, width: 12), // 左側粗邊框顏色提示
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. 第一行：單號 (大字) + 急件標籤
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '#${order.orderId}',
                      style: const TextStyle(
                        fontSize: 20, // 單號加大
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                    if (isUrgent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '急件 URGENT',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16, // 標籤字體加大
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // 2. 第二行：客人名稱 (超大字)
                Text(
                  order.customer,
                  style: const TextStyle(
                    fontSize: 26, // 名字超大，方便老花眼
                    fontWeight: FontWeight.w900,
                    color: Colors.black87,
                  ),
                ),

                const SizedBox(height: 8),

                // 3. 第三行：款式與布料 (大字)
                Row(
                  children: [
                    Icon(Icons.checkroom, size: 28, color: Colors.grey[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        order.item,
                        style: const TextStyle(
                          fontSize: 20, // 內容加大
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // 4. 第四行：交貨日期 (圖示+文字)
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 24,
                      color: Colors.blueGrey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '交貨: ${DateFormat('MM月dd日').format(order.dueDate)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: DateTime.now().isAfter(order.dueDate)
                            ? Colors.red
                            : Colors.blueGrey,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                InkWell(
                  onTap: onFabricToggle,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: order.isFabricOrdered
                          ? Colors.green.withOpacity(0.10)
                          : Colors.orange.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: order.isFabricOrdered
                            ? Colors.green.withOpacity(0.35)
                            : Colors.orange.withOpacity(0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          order.isFabricOrdered
                              ? Icons.check_circle_outline
                              : Icons.local_shipping_outlined,
                          size: 18,
                          color: order.isFabricOrdered
                              ? Colors.green[700]
                              : Colors.orange[800],
                        ),
                        const SizedBox(width: 6),
                        Text(
                          order.isFabricOrdered ? '布料已訂購' : '布料待訂購',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: order.isFabricOrdered
                                ? Colors.green[700]
                                : Colors.orange[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                const Divider(thickness: 1.5), // 分隔線加粗
                const SizedBox(height: 12),

                // 5. 底部：超大操作按鈕
                Row(
                  children: [
                    // 修改按鈕
                    Expanded(
                      child: SizedBox(
                        height: 50, // 按鈕加高
                        child: OutlinedButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit, size: 28),
                          label: const Text(
                            '修改',
                            style: TextStyle(fontSize: 18),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              width: 2,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // 下一步/完成按鈕
                    if (!isCompleted && onNextStage != null)
                      Expanded(
                        flex: 2, // 讓這個按鈕寬度是修改的兩倍
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: onNextStage,
                            icon: const Icon(
                              Icons.arrow_forward,
                              size: 28,
                              color: Colors.white,
                            ),
                            label: const Text(
                              '下一步 / 完成',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              elevation: 2,
                            ),
                          ),
                        ),
                      ),

                    // 封存按鈕 (僅在完成時顯示)
                    if (isCompleted && onArchive != null)
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: onArchive,
                            icon: const Icon(
                              Icons.archive,
                              size: 28,
                              color: Colors.white,
                            ),
                            label: const Text(
                              '封存訂單',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[700],
                            ),
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
  }
}
