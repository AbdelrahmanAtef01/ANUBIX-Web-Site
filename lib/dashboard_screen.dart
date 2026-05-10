import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // <-- Added this for the listener
import 'views/farm_view.dart';
import 'views/tasks_view.dart';
import 'views/analytics_view.dart'; 
import 'views/old_chats_view.dart';
import 'views/history_view.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0; 

  // =========================================================
  // 1. ADDED: SUBSCRIPTION VARIABLE
  // =========================================================
  RealtimeChannel? _consoleSubscription;

  // =========================================================
  // 2. ADDED: START LISTENER ON LOAD
  // =========================================================
  @override
  void initState() {
    super.initState();
    _listenForAutomatedBackendTasks();
  }

  // =========================================================
  // 3. ADDED: THE F12 CONSOLE LISTENER
  // =========================================================
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
            debugPrint("🟢 [SYSTEM ALARM] BACKEND TRIGGER DETECTED!");
            debugPrint("Sender: ${sender.toString().toUpperCase()}");
            debugPrint("Message: $message");
            debugPrint("==============================================\n");
          },
        )
        .subscribe();
  }

  // =========================================================
  // 4. ADDED: CLEANUP ON CLOSE
  // =========================================================
  @override
  void dispose() {
    if (_consoleSubscription != null) {
      Supabase.instance.client.removeChannel(_consoleSubscription!);
    }
    super.dispose();
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0: return const FarmView();
      case 1: return const TasksView();
      case 2: return const HistoryView();
      case 3: return const AnalyticsView(); 
      case 4: return const OldChatsView();
      default: return const FarmView();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🌱 ANUBIX COMMAND CENTER', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index; 
              });
            },
            labelType: NavigationRailLabelType.all,
            backgroundColor: const Color(0xFF1A1A1A),
            indicatorColor: Colors.greenAccent.withOpacity(0.2),
            selectedIconTheme: const IconThemeData(color: Colors.greenAccent),
            selectedLabelTextStyle: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
            unselectedLabelTextStyle: const TextStyle(color: Colors.grey),
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.agriculture), label: Text('Farm')),
              NavigationRailDestination(icon: Icon(Icons.assignment), label: Text('Tasks')),
              NavigationRailDestination(icon: Icon(Icons.history), label: Text('History')),
              NavigationRailDestination(icon: Icon(Icons.bar_chart), label: Text('Analytics')),
              NavigationRailDestination(icon: Icon(Icons.chat), label: Text('Old Chats')),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1, color: Colors.white24), 
          Expanded(child: _buildBody()),
        ],
      ),
    );
  } 
}