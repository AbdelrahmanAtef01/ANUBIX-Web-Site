import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../dashboard_screen.dart';
import '../theme.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const DashboardScreen()));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Login Failed: $e'),
            backgroundColor: AppColors.diseased));
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _signUp() async {
    setState(() => _isLoading = true);
    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (res.user != null) {
        await Supabase.instance.client.from('profiles').upsert({
          'id': res.user!.id,
          'email': res.user!.email,
          'grid_rows': 4,
          'grid_columns': 6,
          'distance_between_plants': 100,
        });
        if (mounted) {
          Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const DashboardScreen()));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Signup Failed: $e'),
            backgroundColor: AppColors.diseased));
      }
    }
    setState(() => _isLoading = false);
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textMuted),
      filled: true,
      fillColor: AppColors.bgPrimary,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.orange, width: 1.5),
      ),
      prefixIcon: Icon(icon, color: AppColors.textMuted),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(44),
          decoration: BoxDecoration(
            color: AppColors.bgSecondary,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withAlpha(80),
                  blurRadius: 30,
                  offset: const Offset(0, 12)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.orange.withAlpha(20),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.orange.withAlpha(60)),
                ),
                child: const Icon(Icons.precision_manufacturing,
                    color: AppColors.orange, size: 40),
              ),
              const SizedBox(height: 20),
              const Text('ANUBIX',
                  style: TextStyle(
                      color: AppColors.orange,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4)),
              const SizedBox(height: 6),
              const Text('Smart Agriculture Dashboard',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      letterSpacing: 0.8)),
              const SizedBox(height: 40),
              TextField(
                controller: _emailController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration:
                    _inputDecoration('Email Address', Icons.email_outlined),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration:
                    _inputDecoration('Password', Icons.lock_outline),
              ),
              const SizedBox(height: 32),
              _isLoading
                  ? const CircularProgressIndicator(color: AppColors.orange)
                  : Column(children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          onPressed: _login,
                          child: const Text('LOGIN',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  letterSpacing: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _signUp,
                        child: const Text('Create New Account',
                            style: TextStyle(color: AppColors.accent)),
                      ),
                    ]),
              const SizedBox(height: 28),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.bgPrimary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('In collaboration with  ',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 11)),
                    Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            color: AppColors.accent, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    const Text('SI-WARE',
                        style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
