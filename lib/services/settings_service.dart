import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  final ValueNotifier<Color> accentColorNotifier = ValueNotifier<Color>(
    const Color(0xFF64B5F6),
  );
  final ValueNotifier<Color> textColorNotifier = ValueNotifier<Color>(
    Colors.white,
  );
  final ValueNotifier<Color> headingTextColorNotifier = ValueNotifier<Color>(
    Colors.white,
  );
  final ValueNotifier<Color> cardTitleColorNotifier = ValueNotifier<Color>(
    Colors.white,
  );
  final ValueNotifier<Color> sidebarTextColorNotifier = ValueNotifier<Color>(
    Colors.white,
  );
  final ValueNotifier<Locale> localeNotifier = ValueNotifier<Locale>(
    const Locale('en'),
  );
  final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(
    ThemeMode.dark,
  );

  // 定義儲存的 Key (鍵值)
  static const String _keyShopName = 'shop_name';
  static const String _keyCurrency = 'currency';
  static const String _keyLanguage = 'language';
  static const String _keyUnit = 'unit';
  static const String _keyNotifications = 'notifications';
  static const String _keyAccentColor = 'accent_color';
  static const String _keyTextColor = 'text_color';
  static const String _keyHeadingTextColor = 'heading_text_color';
  static const String _keyCardTitleColor = 'card_title_color';
  static const String _keySidebarTextColor = 'sidebar_text_color';
  static const String _keyThemeMode = 'theme_mode';

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    accentColorNotifier.value = Color(
      prefs.getInt(_keyAccentColor) ?? 0xFF64B5F6,
    );
    textColorNotifier.value = Color(
      prefs.getInt(_keyTextColor) ?? Colors.white.toARGB32(),
    );
    headingTextColorNotifier.value = Color(
      prefs.getInt(_keyHeadingTextColor) ?? Colors.white.toARGB32(),
    );
    cardTitleColorNotifier.value = Color(
      prefs.getInt(_keyCardTitleColor) ?? Colors.white.toARGB32(),
    );
    sidebarTextColorNotifier.value = Color(
      prefs.getInt(_keySidebarTextColor) ?? Colors.white.toARGB32(),
    );
    final lang = prefs.getString(_keyLanguage) ?? 'English';
    localeNotifier.value = _languageToLocale(lang);
    final themeModeStr = prefs.getString(_keyThemeMode) ?? 'dark';
    themeModeNotifier.value = _stringToThemeMode(themeModeStr);
  }

  // 1. 讀取所有設定 (回傳一個 Map)
  Future<Map<String, dynamic>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'shopName': prefs.getString(_keyShopName) ?? "Alexis Tailor Shop",
      'currency': prefs.getString(_keyCurrency) ?? "HKD",
      'language': prefs.getString(_keyLanguage) ?? "English",
      'unit': prefs.getString(_keyUnit) ?? "Yards",
      'notifications': prefs.getBool(_keyNotifications) ?? true,
      'accentColor': prefs.getInt(_keyAccentColor) ?? 0xFF64B5F6,
      'textColor': prefs.getInt(_keyTextColor) ?? Colors.white.toARGB32(),
      'headingTextColor': prefs.getInt(_keyHeadingTextColor) ?? Colors.white.toARGB32(),
      'cardTitleColor': prefs.getInt(_keyCardTitleColor) ?? Colors.white.toARGB32(),
      'sidebarTextColor': prefs.getInt(_keySidebarTextColor) ?? Colors.white.toARGB32(),
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
    localeNotifier.value = _languageToLocale(value);
  }

  static Locale _languageToLocale(String language) {
    switch (language) {
      case '繁體中文':
        return const Locale('zh', 'TW');
      case '简体中文':
        return const Locale('zh', 'CN');
      case '日本語':
        return const Locale('ja');
      default:
        return const Locale('en');
    }
  }

  static ThemeMode _stringToThemeMode(String s) => switch (s) {
    'light' => ThemeMode.light,
    'system' => ThemeMode.system,
    _ => ThemeMode.dark,
  };

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final str = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      _ => 'dark',
    };
    await prefs.setString(_keyThemeMode, str);
    themeModeNotifier.value = mode;
  }

  Future<void> setUnit(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUnit, value);
  }

  Future<void> setNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotifications, value);
  }

  Future<void> setAccentColor(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyAccentColor, value);
    accentColorNotifier.value = Color(value);
  }

  Future<void> setTextColor(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTextColor, value);
    textColorNotifier.value = Color(value);
  }

  Future<void> setHeadingTextColor(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyHeadingTextColor, value);
    headingTextColorNotifier.value = Color(value);
  }

  Future<void> setCardTitleColor(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCardTitleColor, value);
    cardTitleColorNotifier.value = Color(value);
  }

  Future<void> setSidebarTextColor(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySidebarTextColor, value);
    sidebarTextColorNotifier.value = Color(value);
  }

  // 清除所有設定 (測試用)
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    accentColorNotifier.value = const Color(0xFF64B5F6);
    textColorNotifier.value = Colors.white;
    headingTextColorNotifier.value = Colors.white;
    cardTitleColorNotifier.value = Colors.white;
    sidebarTextColorNotifier.value = Colors.white;
    themeModeNotifier.value = ThemeMode.dark;
  }
}