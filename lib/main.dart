import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

// 導入頁面與佈局
import 'layouts/main_layout.dart';
import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/fabric_page.dart';
import 'pages/pos_page.dart';
import 'pages/workshop_page.dart';
import 'pages/orders_page.dart';
import 'pages/settings_page.dart'; // 如有此檔案請保留，否則請註解
import 'pages/not_found_page.dart';
import 'screens/customers_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const AlexisSystemApp());
}

class AlexisSystemApp extends StatelessWidget {
  const AlexisSystemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alexis Tailor System',
      debugShowCheckedModeBanner: false,
      
      // === 設定深色主題 (Dark Theme) ===
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark, 
        scaffoldBackgroundColor: Colors.black, // 背景純黑
        
        // 自定義顏色方案 (已修正 deprecated 語法)
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF64B5F6), // 淺藍色
          secondary: Color(0xFFFFD54F), // 琥珀色
          surface: Color(0xFF1E1E2C), // 取代 background，設為深灰藍 (卡片底色)
          onSurface: Colors.white, // 取代 onBackground，文字白色
          // error: Colors.redAccent, 
        ),

        // 卡片樣式
        cardTheme: CardThemeData(
          color: const Color(0xFF1E1E2C),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            // 使用新版語法 withValues(alpha: ...)
            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)), 
          ),
        ),

        // AppBar 樣式
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        
        // 輸入框樣式
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2C2C3E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          hintStyle: TextStyle(color: Colors.grey[500]),
        ),
      ),
      
      // === 修正 1：Home 指向 AuthWrapper ===
      home: const AuthWrapper(),
      
      // === 修正 2：路由設定 (補上 child 與 currentRoute) ===
      routes: {
        '/dashboard': (context) => const MainLayout(
          currentRoute: '/dashboard', 
          child: DashboardPage()
        ),
        '/pos': (context) => const MainLayout(
          currentRoute: '/pos', 
          child: POSPage()
        ),
        '/orders': (context) => const MainLayout(
          currentRoute: '/orders', 
          child: OrdersPage()
        ),
        '/customers': (context) => const MainLayout(
          currentRoute: '/customers', 
          child: CustomersScreen()
        ),
        '/inventory': (context) => const MainLayout(
          currentRoute: '/inventory', 
          child: FabricPage()
        ),
        '/workshop': (context) => const MainLayout(
          currentRoute: '/workshop', 
          child: WorkshopPage()
        ),
        '/settings': (context) => const MainLayout(
          currentRoute: '/settings', 
          child: SettingsPage()
        ),
      },
      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (_) => const NotFoundPage()
      ),
    );
  }
}

// === 認證狀態監聽器 ===
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 1. 檢查連線狀態
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 2. 已登入 -> 顯示 Dashboard (需包裹 MainLayout)
        if (snapshot.hasData) {
          return const MainLayout(
            currentRoute: '/dashboard', 
            child: DashboardPage()
          );
        }

        // 3. 未登入 -> 顯示登入頁面
        return const LoginPage();
      },
    );
  }
}