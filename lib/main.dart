import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'views/login_view.dart';
import 'dashboard_screen.dart'; 

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Your exact URL and Anon Key
  await Supabase.initialize(
    url: 'https://bdkutmmrcjckaazzzspe.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJka3V0bW1yY2pja2Fhenp6c3BlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI0NTQ2MjUsImV4cCI6MjA4ODAzMDYyNX0.GiMir_2cYgI_2WXA6kfY7om6WFX5ZiYsc7swx-ZbsuY', 
  );

  // Fallback: If you ever get completely stuck again, uncomment the line below to force a wipe.
  // await Supabase.instance.client.auth.signOut();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Anubix Dashboard',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      // We now use the AuthWrapper instead of a simple ternary check
      home: const AuthWrapper(),
    );
  }
}

// --- PROFESSIONAL AUTH ROUTING ---
// This listens to the live session stream. If the token is invalid, it guarantees the Login Screen appears.
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // Show a loading spinner while checking the database connection
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Colors.greenAccent),
            ),
          );
        }

        // Get the current session status
        final session = snapshot.hasData ? snapshot.data!.session : null;

        // If there is no valid session, explicitly route to the Login View
        if (session == null) {
          return const LoginView();
        }

        // If a valid session exists, route to the Command Center
        return const DashboardScreen();
      },
    );
  }
}