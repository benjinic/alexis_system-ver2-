import 'package:flutter/material.dart';
import '../models/order.dart';

class CartProvider with ChangeNotifier {
  // 內部儲存購物車項目
  final List<OrderItem> _items = [];

  // 外部讀取用的 getter (避免直接修改 List)
  List<OrderItem> get items => List.unmodifiable(_items);

  // === 核心功能 ===

  // 新增項目
  void addItem(OrderItem item) {
    _items.add(item);
    notifyListeners(); // 通知 UI 更新
  }

  // 更新項目 (用於編輯功能)
  void updateItem(int index, OrderItem newItem) {
    if (index >= 0 && index < _items.length) {
      _items[index] = newItem;
      notifyListeners();
    }
  }

  // 移除項目
  void removeItem(int index) {
    if (index >= 0 && index < _items.length) {
      _items.removeAt(index);
      notifyListeners();
    }
  }

  // 清空購物車
  void clearCart() {
    _items.clear();
    notifyListeners();
  }

  // 載入現有訂單 (用於編輯舊訂單時)
  void loadOrderItems(List<OrderItem> items) {
    _items.clear();
    _items.addAll(items);
    notifyListeners();
  }

  // === 計算邏輯 ===

  // 計算小計 (Subtotal)
  double get subtotal => _items.fold(
    0, 
    (sum, item) => sum + (item.price * item.quantity)
  );

  // 計算總成本 (Total Cost)
  double get totalCost => _items.fold(
    0, 
    (sum, item) => sum + (item.cost * item.quantity)
  );
  
  // 檢查是否為空
  bool get isEmpty => _items.isEmpty;
}