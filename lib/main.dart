import 'package:flutter/material.dart';
import 'package:moe/features/school/presentation/providers/assessment_provider.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'core/constants/app_colors.dart';
import 'core/constants/app_font.dart';
import 'core/services/local_storage_service.dart';
import 'core/services/parent_local_storage_service.dart';
import 'core/services/student_local_storage_service.dart';
import 'core/services/textbooks_teaching_local_storage.dart';
import 'core/services/data_preloader_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_theme.dart' as AppTheme;
import 'core/theme/theme_provider.dart';
import 'features/school/presentation/providers/school_provider.dart';
import 'routing/app_router.dart';
import 'features/auth/presentation/providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final appDir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(appDir.path);
    await LocalStorageService.init();
    await ParentLocalStorageService.init();
    // await TextbooksTeachingLocalStorageService.init();
    // await StudentLocalStorageService.init();
  } catch (e, stack) {
    debugPrint('Init error: $e\n$stack');
  }

  // Create auth provider first
  final authProvider = AuthProvider();

  // Wait for auth data to load
  await authProvider.waitForInitialization();

  // Run app
  runApp(MyApp(authProvider: authProvider));
}

class MyApp extends StatelessWidget {
  final AuthProvider authProvider;

  const MyApp({super.key, required this.authProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => SchoolProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AssessmentProvider()),
      ],
      child: Consumer2<AuthProvider, ThemeProvider>(
        builder: (context, authProvider, themeProvider, _) {
          return MaterialApp.router(
            title: 'School Quality Assessment',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.currentTheme.copyWith(
              textTheme: themeProvider.currentTheme.textTheme.apply(
                fontFamily: AppFont.primaryFont,
              ),
              appBarTheme: themeProvider.currentTheme.appBarTheme.copyWith(
                titleTextStyle: TextStyle(
                  fontFamily: AppFont.primaryFont,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  textStyle: const TextStyle(fontFamily: AppFont.primaryFont),
                ),
              ),
            ),
            routerConfig: createRouter(authProvider),
            builder: (context, routerChild) {
              return DefaultTextStyle(
                style: TextStyle(
                  fontFamily: AppFont.primaryFont,
                  fontSize: 16.0,
                  height: 1.5,
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                ),
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
                  child: ConnectivitySnackbarWrapper(
                    child: routerChild ?? const SizedBox.shrink(),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// Add this extension to AuthProvider to wait for initialization
extension AuthProviderExtension on AuthProvider {
  Future<void> waitForInitialization() async {
    // The constructor already calls _loadData()
    // Just wait for loading to complete
    while (isLoading) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }
}

// Connectivity Snackbar Wrapper
class ConnectivitySnackbarWrapper extends StatefulWidget {
  final Widget child;

  const ConnectivitySnackbarWrapper({super.key, required this.child});

  @override
  State<ConnectivitySnackbarWrapper> createState() => _ConnectivitySnackbarWrapperState();
}

class _ConnectivitySnackbarWrapperState extends State<ConnectivitySnackbarWrapper> {
  bool _wasOffline = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _listenToConnectivity();
  }

  void _listenToConnectivity() {
    LocalStorageService.onlineStatusStream.listen((isOnline) {
      if (!mounted) return;

      // Don't show anything on initial load
      if (!_initialized) {
        _initialized = true;
        _wasOffline = !isOnline;
        return;
      }

      // Show snackbar when connectivity changes
      if (isOnline && _wasOffline) {
        // Came back online
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.wifi, color: Colors.white, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '✓ Back Online',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3), // Changed from 5 to 3
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(10),
          ),
        );
      } else if (!isOnline && !_wasOffline) {
        // Went offline
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.wifi_off, color: Colors.white, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Offline Mode - Saving Locally',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(10),
          ),
        );
      }

      _wasOffline = !isOnline;
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}