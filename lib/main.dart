import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/cart_provider.dart';
import 'services/settings_service.dart';
import 'l10n/app_localizations.dart';

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
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _initializeAppCheck();
  await SettingsService().initialize();
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => CartProvider())],
      child: const AlexisSystemApp(),
    ),
  );
}

Future<void> _initializeAppCheck() async {
  const recaptchaSiteKey = String.fromEnvironment(
    'FIREBASE_APPCHECK_RECAPTCHA_KEY',
  );

  await FirebaseAppCheck.instance.activate(
    providerWeb: recaptchaSiteKey.isEmpty
        ? null
        : ReCaptchaV3Provider(recaptchaSiteKey),
    providerAndroid: const AndroidPlayIntegrityProvider(),
    providerApple: const AppleAppAttestWithDeviceCheckFallbackProvider(),
  );
}

class AlexisSystemApp extends StatefulWidget {
  const AlexisSystemApp({super.key});

  @override
  State<AlexisSystemApp> createState() => _AlexisSystemAppState();
}

class _AlexisSystemAppState extends State<AlexisSystemApp> {
  final SettingsService _settingsService = SettingsService();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _settingsService.accentColorNotifier,
        _settingsService.textColorNotifier,
        _settingsService.headingTextColorNotifier,
        _settingsService.cardTitleColorNotifier,
        _settingsService.sidebarTextColorNotifier,
        _settingsService.localeNotifier,
      ]),
      builder: (context, child) {
        final accentColor = _settingsService.accentColorNotifier.value;
        final textColor = _settingsService.textColorNotifier.value;
        final headingTextColor =
            _settingsService.headingTextColorNotifier.value;
        final cardTitleColor = _settingsService.cardTitleColorNotifier.value;
        final sidebarTextColor =
            _settingsService.sidebarTextColorNotifier.value;
        final locale = _settingsService.localeNotifier.value;
        return MaterialApp(
          title: 'Alexis Tailor System',
          debugShowCheckedModeBanner: false,
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en'),
            Locale('zh', 'TW'),
            Locale('zh', 'CN'),
          ],

          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: Colors.black,
            fontFamily: 'NotoSansTC',
            fontFamilyFallback: const ['NotoSansTC'],
            colorScheme: ColorScheme.dark(
              primary: accentColor,
              secondary: const Color(0xFFFFD54F),
              surface: const Color(0xFF1E1E2C),
              onSurface: textColor,
            ),
            textTheme: ThemeData.dark().textTheme
                .apply(bodyColor: textColor, displayColor: headingTextColor)
                .merge(
                  TextTheme(
                    titleLarge: TextStyle(color: cardTitleColor),
                    titleMedium: TextStyle(color: cardTitleColor),
                    titleSmall: TextStyle(color: cardTitleColor),
                    labelLarge: TextStyle(color: cardTitleColor),
                    labelMedium: TextStyle(color: cardTitleColor),
                    labelSmall: TextStyle(color: cardTitleColor),
                  ),
                ),
            primaryTextTheme: ThemeData.dark().primaryTextTheme
                .apply(bodyColor: textColor, displayColor: headingTextColor)
                .merge(
                  TextTheme(
                    titleLarge: TextStyle(color: cardTitleColor),
                    titleMedium: TextStyle(color: cardTitleColor),
                    titleSmall: TextStyle(color: cardTitleColor),
                    labelLarge: TextStyle(color: cardTitleColor),
                    labelMedium: TextStyle(color: cardTitleColor),
                    labelSmall: TextStyle(color: cardTitleColor),
                  ),
                ),
            cardTheme: CardThemeData(
              color: const Color(0xFF1E1E2C),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.black,
              foregroundColor: textColor,
              elevation: 0,
            ),
            listTileTheme: ListTileThemeData(
              textColor: textColor,
              iconColor: textColor,
            ),
            iconTheme: IconThemeData(color: textColor),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF2C2C3E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              labelStyle: TextStyle(color: cardTitleColor),
              hintStyle: TextStyle(color: Colors.grey[500]),
            ),
            navigationRailTheme: NavigationRailThemeData(
              selectedLabelTextStyle: TextStyle(
                color: sidebarTextColor,
                fontSize: 11,
              ),
              unselectedLabelTextStyle: TextStyle(
                color: sidebarTextColor.withValues(alpha: 0.6),
                fontSize: 11,
              ),
              selectedIconTheme: IconThemeData(color: sidebarTextColor),
              unselectedIconTheme: IconThemeData(
                color: sidebarTextColor.withValues(alpha: 0.6),
              ),
            ),
          ),

          home: const AuthWrapper(),
          routes: {
            '/dashboard': (context) => const MainLayout(
              currentRoute: '/dashboard',
              child: DashboardPage(),
            ),
            '/pos': (context) =>
                const MainLayout(currentRoute: '/pos', child: POSPage()),
            '/orders': (context) =>
                const MainLayout(currentRoute: '/orders', child: OrdersPage()),
            '/customers': (context) => const MainLayout(
              currentRoute: '/customers',
              child: CustomersScreen(),
            ),
            '/inventory': (context) => const MainLayout(
              currentRoute: '/inventory',
              child: FabricPage(),
            ),
            '/workshop': (context) =>
                MainLayout(currentRoute: '/workshop', child: WorkshopPage()),
            '/settings': (context) => const MainLayout(
              currentRoute: '/settings',
              child: SettingsPage(),
            ),
          },
          onUnknownRoute: (settings) =>
              MaterialPageRoute(builder: (_) => const NotFoundPage()),
        );
      },
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
            child: DashboardPage(),
          );
        }

        // 3. 未登入 -> 顯示登入頁面
        return const LoginPage();
      },
    );
  }
}
