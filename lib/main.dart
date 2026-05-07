import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'core/auth_provider.dart';
import 'core/shop_provider.dart';
import 'core/data_refresh_notifier.dart';
import 'core/app_config.dart';
import 'core/connectivity_service.dart';
import 'widgets/main_layout.dart';

// Import screens...
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/create_password_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/shop/shop_select_screen.dart';
import 'screens/shop/home_screen.dart';
import 'screens/shop/kena_beca_screen.dart';
import 'screens/shop/len_den_screen.dart';
import 'screens/shop/ay_bay_screen.dart';
import 'screens/shop/new_purchase_screen.dart';
import 'screens/shop/new_sale_screen.dart';
import 'screens/shop/products_screen.dart';
import 'screens/shop/add_product_screen.dart';
import 'screens/shop/parties_screen.dart';
import 'screens/shop/add_person_screen.dart';
import 'screens/shop/returns_screen.dart';
import 'screens/shop/wallets_screen.dart';
import 'screens/shop/settings_screen.dart';
import 'screens/shop/profile_screen.dart';
import 'screens/shop/invoice_settings_screen.dart';
import 'screens/shop/employees_screen.dart';
import 'screens/shop/categories_screen.dart';
import 'screens/shop/all_sales_screen.dart';
import 'screens/shop/all_purchases_screen.dart';
import 'screens/shop/invoice_view_screen.dart';
import 'screens/shop/approvals_screen.dart';
import 'screens/shop/person_ledger_screen.dart';
import 'screens/shop/new_transaction_screen.dart';
import 'screens/shop/activity_history_screen.dart';
import 'screens/shop/notifications_screen.dart';
import 'screens/shop/privacy_policy_screen.dart';
import 'screens/shop/terms_service_screen.dart';
import 'screens/shop/daily_report_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.init();

  final dsn = AppConfig.sentryDsn;
  final isDsnValid = dsn.isNotEmpty && dsn != 'REPLACE_WITH_YOUR_SENTRY_DSN';

  if (!isDsnValid) {
    // Run app without Sentry if DSN is missing or placeholder
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ShopProvider()),
          ChangeNotifierProvider(create: (_) => ConnectivityService()),
          ChangeNotifierProvider(create: (_) => DataRefreshNotifier()),
        ],
        child: const MyApp(),
      ),
    );
    return;
  }

  await SentryFlutter.init(
    (options) {
      options.dsn = dsn;
      options.tracesSampleRate = 1.0;
    },
    appRunner: () async {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );

      runApp(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => ShopProvider()),
            ChangeNotifierProvider(create: (_) => ConnectivityService()),
            ChangeNotifierProvider(create: (_) => DataRefreshNotifier()),
          ],
          child: const MyApp(),
        ),
      );
    },
  );
}

// Router configuration
GoRouter _createRouter(AuthProvider authProvider, ShopProvider shopProvider) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: Listenable.merge([authProvider, shopProvider]),
    redirect: (context, state) {
      final isLoggedIn = authProvider.session != null;
      final isAuthRoute = state.uri.path.startsWith('/login') || 
                          state.uri.path.startsWith('/signup') || 
                          state.uri.path.startsWith('/create-password') || 
                          state.uri.path.startsWith('/forgot-password') || 
                          state.uri.path.startsWith('/reset-password') ||
                          state.uri.path == '/splash';

      if (authProvider.loading) return null;

      if (!isLoggedIn && !isAuthRoute) {
        return '/login';
      }

      if (isLoggedIn && isAuthRoute) {
        return '/shop-select';
      }

      final hasActiveShop = shopProvider.currentShop != null;
      final isShopSelectRoute = state.uri.path == '/shop-select';
      final isOnboardingRoute = state.uri.path == '/onboarding';
      final isProfileRoute = state.uri.path == '/profile';

      if (isLoggedIn && !hasActiveShop && !isShopSelectRoute && !isAuthRoute && !isOnboardingRoute && !isProfileRoute) {
        return '/shop-select';
      }

      // If user goes to / and has an active shop, redirect to shop-home
      if (state.uri.path == '/' && hasActiveShop) {
        return '/shop-home';
      }

      // Automatically navigate away from shop-select if a shop is activated
      if (hasActiveShop && isShopSelectRoute) {
        return '/shop-home';
      }

      return null;
    },
    routes: <RouteBase>[
      // Public routes
      GoRoute(
        path: '/onboarding',
        builder: (BuildContext context, GoRouterState state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/splash',
        builder: (BuildContext context, GoRouterState state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (BuildContext context, GoRouterState state) => const LoginScreen(),
      ),
        GoRoute(
          path: '/create-password',
          builder: (context, state) => CreatePasswordScreen(email: state.extra as String),
        ),
        GoRoute(
          path: '/signup',
          builder: (context, state) => const SignupScreen(),
        ),
      GoRoute(
        path: '/forgot-password',
        builder: (BuildContext context, GoRouterState state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (BuildContext context, GoRouterState state) => const ResetPasswordScreen(),
      ),

      // Shop selection (auth required)
      GoRoute(
        path: '/shop-select',
        builder: (BuildContext context, GoRouterState state) => const ShopSelectScreen(),
      ),

      // Protected + shop required routes (Wrapped in MainLayout)
      ShellRoute(
        builder: (context, state, child) => MainLayout(
          key: ValueKey('main_layout_${shopProvider.currentShop?.id}'),
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/shop-home',
            builder: (context, state) => HomeScreen(key: ValueKey('shop_home_${shopProvider.currentShop?.id}')),
          ),
          GoRoute(
            path: '/kena-becha',
            builder: (context, state) => KenaBecaScreen(key: ValueKey('kena_becha_${shopProvider.currentShop?.id}')),
          ),
          GoRoute(
            path: '/len-den',
            builder: (context, state) => LenDenScreen(key: ValueKey('len_den_${shopProvider.currentShop?.id}')),
          ),
          GoRoute(
            path: '/ay-bay',
            builder: (context, state) => AyBayScreen(key: ValueKey('ay_bay_${shopProvider.currentShop?.id}')),
          ),
        ],
      ),

      GoRoute(
        path: '/all-purchases',
        builder: (BuildContext context, GoRouterState state) => const AllPurchasesScreen(),
      ),
      GoRoute(
        path: '/all-sales',
        builder: (BuildContext context, GoRouterState state) => const AllSalesScreen(),
      ),
      GoRoute(
        path: '/new-transaction',
        builder: (BuildContext context, GoRouterState state) => const NewTransactionScreen(),
      ),
      GoRoute(
        path: '/new-purchase',
        builder: (BuildContext context, GoRouterState state) => NewPurchaseScreen(editPurchase: state.extra as Map<String, dynamic>?),
      ),
      GoRoute(
        path: '/new-sale',
        builder: (BuildContext context, GoRouterState state) => NewSaleScreen(editSale: state.extra as Map<String, dynamic>?),
      ),
      GoRoute(
        path: '/products',
        builder: (BuildContext context, GoRouterState state) => const ProductsScreen(),
      ),
      GoRoute(
        path: '/add-product',
        builder: (BuildContext context, GoRouterState state) => AddProductScreen(editProduct: state.extra),
      ),
      GoRoute(
        path: '/ledger/:id/:name',
        builder: (BuildContext context, GoRouterState state) {
          final id = state.pathParameters['id']!;
          final name = state.pathParameters['name']!;
          return PersonLedgerScreen(personId: id, personName: name);
        },
      ),
      GoRoute(
        path: '/parties',
        builder: (BuildContext context, GoRouterState state) => const PartiesScreen(),
      ),
      GoRoute(
        path: '/add-person',
        builder: (BuildContext context, GoRouterState state) {
          final extras = state.extra as Map<String, dynamic>?;
          return AddPersonScreen(
            initialType: extras?['type'] ?? 'customer',
            editPerson: extras?['person'],
          );
        },
      ),
      GoRoute(
        path: '/returns',
        builder: (BuildContext context, GoRouterState state) => const ReturnsScreen(),
      ),
      GoRoute(
        path: '/categories',
        builder: (BuildContext context, GoRouterState state) => const CategoriesScreen(),
      ),
      GoRoute(
        path: '/wallets',
        builder: (BuildContext context, GoRouterState state) => const WalletsScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (BuildContext context, GoRouterState state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (BuildContext context, GoRouterState state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/invoice-settings',
        builder: (BuildContext context, GoRouterState state) => const InvoiceSettingsScreen(),
      ),
      GoRoute(
        path: '/employees',
        builder: (BuildContext context, GoRouterState state) => const EmployeesScreen(),
      ),
      GoRoute(
        path: '/invoice/:type/:id',
        builder: (BuildContext context, GoRouterState state) {
          final type = state.pathParameters['type']!;
          final id = state.pathParameters['id']!;
          return InvoiceViewScreen(type: type, id: id);
        },
      ),
      GoRoute(
        path: '/notifications',
        builder: (BuildContext context, GoRouterState state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/approvals',
        builder: (BuildContext context, GoRouterState state) => const ApprovalsScreen(),
      ),
      GoRoute(
        path: '/activity-history',
        builder: (BuildContext context, GoRouterState state) => const ActivityHistoryScreen(),
      ),
      GoRoute(
        path: '/daily-report',
        builder: (BuildContext context, GoRouterState state) => const DailyReportScreen(),
      ),
      GoRoute(
        path: '/privacy',
        builder: (BuildContext context, GoRouterState state) => const PrivacyPolicyScreen(),
      ),
      GoRoute(
        path: '/terms',
        builder: (BuildContext context, GoRouterState state) => const TermsOfServiceScreen(),
      ),
    ],
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  GoRouter? _router;
  String? _lastShopId;

  @override
  void initState() {
    super.initState();
    // Router is now initialized in build to handle shop-specific resets
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.select<AuthProvider, bool>((p) => p.loading);
    // We do not need to watch shopProvider here anymore since it's just for GoRouter!

    if (isLoading) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final shopId = context.watch<ShopProvider>().currentShop?.id;

    // Recreate the router instance if the shop changes to ensure a clean state
    if (_router == null || shopId != _lastShopId) {
      _router = _createRouter(context.read<AuthProvider>(), context.read<ShopProvider>());
      _lastShopId = shopId;
    }

    return MaterialApp.router(
      key: ValueKey('papyrus_app_$shopId'),
      title: 'Papyrus',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF154834), // Papyrus Dark Green
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.light,
      routerConfig: _router,
    );
  }
}
