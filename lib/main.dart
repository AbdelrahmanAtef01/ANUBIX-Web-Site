import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'views/login_view.dart';
import 'dashboard_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://bdkutmmrcjckaazzzspe.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJka3V0bW1yY2pja2Fhenp6c3BlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI0NTQ2MjUsImV4cCI6MjA4ODAzMDYyNX0.GiMir_2cYgI_2WXA6kfY7om6WFX5ZiYsc7swx-ZbsuY',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ANUBIX | Smart Agriculture Dashboard',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.bgPrimary,
        colorScheme: ColorScheme.dark(
          primary: AppColors.orange,
          secondary: AppColors.accent,
          surface: AppColors.bgSecondary,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.bgPrimary,
          elevation: 0,
        ),
        dividerTheme: const DividerThemeData(color: AppColors.border),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
                child: CircularProgressIndicator(color: AppColors.orange)),
          );
        }
        final session = snapshot.hasData ? snapshot.data!.session : null;
        if (session == null) return const LoginView();
        return const DashboardScreen();
      },
    );
  }
}
