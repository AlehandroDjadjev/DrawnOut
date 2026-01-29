import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'pages/login.dart';
import 'pages/signup.dart';
import 'pages/home.dart';
import 'pages/lessons_page.dart';
import 'pages/settings_page.dart';
import 'providers/developer_mode_provider.dart';
import 'services/app_config_service.dart';
import 'theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: 'assets/.env');
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => DeveloperModeProvider()),
        ChangeNotifierProvider(create: (_) => AppConfigService()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ThemeData _buildTheme(bool dark) {
    final base = dark ? ThemeData.dark() : ThemeData.light();
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: dark ? Colors.tealAccent.shade200 : Colors.blue,
        secondary: dark ? Colors.tealAccent : Colors.blueAccent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              dark ? Colors.tealAccent.shade200 : Colors.blueAccent,
          foregroundColor: dark ? Colors.black : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 3,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: dark ? Colors.tealAccent.shade200 : Colors.blue,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DrawnOut',
      theme: _buildTheme(themeProvider.isDarkMode),
      routes: {
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const SignupPage(),
        '/home': (context) => const HomePage(),
        '/lessons': (context) => const LessonsPage(),
        '/settings': (context) => const SettingsPage(),
      },
      initialRoute: '/login',
    );
  }
}

