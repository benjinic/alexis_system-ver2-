import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  // 定義儲存的 Key (鍵值)
  static const String _keyShopName = 'shop_name';
  static const String _keyCurrency = 'currency';
  static const String _keyLanguage = 'language';
  static const String _keyUnit = 'unit';
  static const String _keyNotifications = 'notifications';

  // 1. 讀取所有設定 (回傳一個 Map)
  Future<Map<String, dynamic>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'shopName': prefs.getString(_keyShopName) ?? "Alexis Tailor Shop",
      'currency': prefs.getString(_keyCurrency) ?? "HKD",
      'language': prefs.getString(_keyLanguage) ?? "English",
      'unit': prefs.getString(_keyUnit) ?? "Yards",
      'notifications': prefs.getBool(_keyNotifications) ?? true,
    };
  }

  // 2. 儲存個別設定
  Future<void> setShopName(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyShopName, value);
  }

  Future<void> setCurrency(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCurrency, value);
  }

  Future<void> setLanguage(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLanguage, value);
  }

  Future<void> setUnit(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUnit, value);
  }

  Future<void> setNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotifications, value);
  }
  
  // 清除所有設定 (測試用)
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}