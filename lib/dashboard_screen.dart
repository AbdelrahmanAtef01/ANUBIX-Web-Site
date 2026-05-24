import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'views/farm_view.dart';
import 'views/tasks_view.dart';
import 'views/analytics_view.dart';
import 'views/old_chats_view.dart';
import 'views/history_view.dart';
import 'views/config_view.dart';
import 'theme.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  RealtimeChannel? _consoleSubscription;

  @override
  void initState() {
    super.initState();
    _listenForAutomatedBackendTasks();
  }

  void _listenForAutomatedBackendTasks() {
    _consoleSubscription = Supabase.instance.client
        .channel('global_dashboard_listener')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chats',
          callback: (payload) {
            final sender = payload.newRecord['sender'];
            final message = payload.newRecord['message'];
            debugPrint("\n==============================================");
            debugPrint("[SYSTEM] BACKEND TRIGGER DETECTED!");
            debugPrint("Sender: ${sender.toString().toUpperCase()}");
            debugPrint("Message: $message");
            debugPrint("==============================================\n");
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_consoleSubscription != null) {
      Supabase.instance.client.removeChannel(_consoleSubscription!);
    }
    super.dispose();
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return const FarmView();
      case 1:
        return const OldChatsView();
      case 2:
        return const TasksView();
      case 3:
        return const HistoryView();
      case 4:
        return const AnalyticsView();
      case 5:
        return const ConfigView();
      default:
        return const FarmView();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bgPrimary,
        elevation: 0,
        toolbarHeight: 56,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.orange.withAlpha(80)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.precision_manufacturing, color: AppColors.orange, size: 20),
                  SizedBox(width: 8),
                  Text('ANUBIX',
                      style: TextStyle(
                        color: AppColors.orange,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        letterSpacing: 2.5,
                      )),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Container(width: 1, height: 24, color: AppColors.border),
            const SizedBox(width: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.bgSecondary,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                        color: AppColors.accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  const Text('SI-WARE',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        letterSpacing: 1.2,
                      )),
                ],
              ),
            ),
            const Spacer(),
            const Text('Smart Agriculture Dashboard',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    letterSpacing: 0.5)),
          ],
        ),
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() => _selectedIndex = index);
            },
            labelType: NavigationRailLabelType.all,
            backgroundColor: AppColors.bgSecondary,
            indicatorColor: AppColors.orange.withAlpha(40),
            selectedIconTheme: const IconThemeData(color: AppColors.orange),
            selectedLabelTextStyle: const TextStyle(
                color: AppColors.orange,
                fontWeight: FontWeight.bold,
                fontSize: 12),
            unselectedIconTheme:
                const IconThemeData(color: AppColors.textMuted),
            unselectedLabelTextStyle:
                const TextStyle(color: AppColors.textMuted, fontSize: 11),
            leading: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.orange.withAlpha(18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.orange.withAlpha(50)),
                ),
                child: const Icon(Icons.precision_manufacturing,
                    color: AppColors.orange, size: 22),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                  icon: Icon(Icons.agriculture), label: Text('Farm')),
              NavigationRailDestination(
                  icon: Icon(Icons.chat), label: Text('Chats')),
              NavigationRailDestination(
                  icon: Icon(Icons.assignment), label: Text('Tasks')),
              NavigationRailDestination(
                  icon: Icon(Icons.history), label: Text('History')),
              NavigationRailDestination(
                  icon: Icon(Icons.bar_chart), label: Text('Analytics')),
              NavigationRailDestination(
                  icon: Icon(Icons.settings), label: Text('Config')),
            ],
          ),
          Container(width: 1, color: AppColors.border),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}
