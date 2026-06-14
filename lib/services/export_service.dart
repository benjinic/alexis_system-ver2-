import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../models/order.dart';
import '../models/customer.dart';

class ExportService {
  /// 將訂單列表匯出為 CSV 並分享
  Future<void> exportOrdersToCsv(List<Order> orders) async {
    // 1. 準備 CSV 數據
    List<List<dynamic>> rows = [];

    // 加入表頭 (Header)
    rows.add([
      'Order ID',
      'Date',
      'Customer Name',
      'Items Summary',
      'Total Amount',
      'Deposit',
      'Balance',
      'Status',
      'Payment Method',
    ]);

    // 加入每一筆訂單數據
    for (var order in orders) {
      // 格式化日期
      String dateStr = order.createdAt != null
          ? DateFormat('yyyy-MM-dd HH:mm').format(order.createdAt!)
          : '';

      // 產生商品摘要 (例如: "Suit ($1200), Shirt ($300)")
      String itemsStr = order.items
          .map((i) => '${i.service} (\$${i.price.toInt()})')
          .join('; ');

      rows.add([
        order.id,
        dateStr,
        order.customerName,
        itemsStr,
        order.total,
        order.deposit,
        order.balance,
        order.status,
        order.paymentMethod,
      ]);
    }

    // 2. 將列表轉換為 CSV 字串，並加入 BOM 以提升 Excel 相容性
    final csvData = const ListToCsvConverter().convert(rows);
    final csvWithBom = '\uFEFF$csvData'; // Excel-friendly BOM

    // 3. 依平台處理輸出與分享
    if (kIsWeb) {
      // Web: 直接分享文字內容（瀏覽器的 Web Share API 若可用）
      await Share.share(csvWithBom, subject: 'Alexis Orders Export');
      return;
    }

    // 非 Web：寫入暫存檔並分享
    final directory = await getTemporaryDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final path = '${directory.path}/alexis_orders_$timestamp.csv';
    final file = File(path);

    // 使用位元組寫入以確保 BOM 正確
    await file.writeAsBytes(utf8.encode(csvWithBom), flush: true);

    // 喚起系統分享選單
    await Share.shareXFiles([
      XFile(path, mimeType: 'text/csv', name: 'alexis_orders_$timestamp.csv'),
    ], text: 'Alexis orders export CSV file.');
  }

  /// 將訂單展開為單項明細的 CSV 字串（靜態方法）
  static String generateItemDetailsCSV(List<Order> orders) {
    List<List<dynamic>> rows = [
      [
        'Date',
        'Customer Name',
        'Service/Item',
        'Quantity',
        'Unit Price',
        'Order Total',
        'Status',
      ],
    ];

    for (var order in orders) {
      final dateStr = order.createdAt != null
          ? DateFormat('yyyy-MM-dd HH:mm').format(order.createdAt!)
          : '';
      for (var item in order.items) {
        rows.add([
          dateStr,
          order.customerName,
          item.serviceName ?? item.service,
          item.quantity,
          item.price,
          order.total,
          order.status,
        ]);
      }
    }

    return const ListToCsvConverter().convert(rows);
  }

  /// 將客戶列表轉換為對齊的 CSV 字串（靜態方法）
  static String generateCustomersCSV(List<Customer> customers) {
    List<List<dynamic>> rows = [
      [
        'Customer Name',
        'Phone',
        'Email',
        'Orders Count',
        'Total Spent',
        'Created At',
      ],
    ];

    for (var customer in customers) {
      rows.add([
        customer.name,
        customer.phone,
        customer.email,
        customer.orders,
        customer.totalSpent,
        customer.createdAt != null
            ? DateFormat('yyyy-MM-dd').format(customer.createdAt!)
            : '',
      ]);
    }

    return const ListToCsvConverter().convert(rows);
  }

  /// 將客戶列表匯出為 CSV 並分享
  Future<void> exportCustomersToCsv(List<Customer> customers) async {
    final csvData = generateCustomersCSV(customers);

    final csvWithBom = '\uFEFF$csvData';
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

    if (kIsWeb) {
      await Share.share(csvWithBom, subject: 'Alexis Customers Export');
      return;
    }

    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/alexis_customers_$timestamp.csv';
    final file = File(path);
    await file.writeAsBytes(utf8.encode(csvWithBom), flush: true);
    await Share.shareXFiles([
      XFile(
        path,
        mimeType: 'text/csv',
        name: 'alexis_customers_$timestamp.csv',
      ),
    ], text: 'Alexis customers export CSV file.');
  }
}
