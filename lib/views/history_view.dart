import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart'; // Add this to pubspec.yaml for date formatting

class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  String _searchQuery = "";
  String _sortBy = "execution_time"; // Default sort
  bool _ascending = false; // Newest first

  // --- UI ICON LOGIC ---
  IconData _getIconForTask(String type) {
    switch (type.toLowerCase()) {
      case 'water': return Icons.water_drop;
      case 'scan_plant': return Icons.qr_code_scanner;
      case 'alert': return Icons.warning_amber_rounded;
      case 'navigation': return Icons.location_on;
      default: return Icons.settings_backup_restore;
    }
  }

  Color _getColorForTask(String type) {
    if (type.contains('alert')) return Colors.redAccent;
    if (type.contains('water')) return Colors.blueAccent;
    if (type.contains('scan')) return Colors.greenAccent;
    return Colors.white54;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- HEADER & SEARCH ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('System Command Log', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
              _buildSearchBar(),
            ],
          ),
          const SizedBox(height: 20),

          // --- SORTING CHIPS ---
          Row(
            children: [
              const Text('Sort by:', style: TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(width: 10),
              _sortChip('Date', 'execution_time'),
              _sortChip('Location', 'plant_location'),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _ascending = !_ascending),
                icon: Icon(_ascending ? Icons.arrow_upward : Icons.arrow_downward, size: 16),
                label: Text(_ascending ? "Oldest First" : "Newest First"),
                style: TextButton.styleFrom(foregroundColor: Colors.blueAccent),
              )
            ],
          ),
          const SizedBox(height: 30),

          // --- REAL-TIME LOG STREAM ---
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client
                  .from('task_history')
                  .stream(primaryKey: ['task_id'])
                  .order(_sortBy, ascending: _ascending),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                
                var logs = snapshot.data ?? [];
                
                // Client-side search filtering
                if (_searchQuery.isNotEmpty) {
                  logs = logs.where((l) => 
                    l['task_type'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
                    l['plant_location'].toString().contains(_searchQuery)
                  ).toList();
                }

                if (logs.isEmpty) return const Center(child: Text("No records found in command history."));

                return ListView.separated(
                  itemCount: logs.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    return _buildLogItem(log);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- LOG ITEM UI (Matching your screenshot) ---
  Widget _buildLogItem(Map<String, dynamic> log) {
    final type = log['task_type'] ?? 'Unknown';
    final location = log['plant_location'] ?? 'N/A';
    final status = log['status'] ?? 'Completed';
    final time = DateTime.parse(log['execution_time']).toLocal();
    final timeStr = DateFormat('MMM d, hh:mm a').format(time);

    final color = _getColorForTask(type.toLowerCase());

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(_getIconForTask(type), color: color, size: 24),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatTaskTitle(type), style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(timeStr, style: const TextStyle(color: Colors.white24, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_getTaskDescription(type, status), style: const TextStyle(color: Colors.white54, fontSize: 14)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 14, color: Colors.white24),
                    const SizedBox(width: 4),
                    Text("Location: ($location)", style: const TextStyle(color: Colors.white24, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- HELPER UI WIDGETS ---
  Widget _buildSearchBar() {
    return SizedBox(
      width: 300,
      height: 45,
      child: TextField(
        onChanged: (val) => setState(() => _searchQuery = val),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: "Search logs...",
          hintStyle: const TextStyle(color: Colors.white24),
          prefixIcon: const Icon(Icons.search, color: Colors.white24, size: 20),
          filled: true,
          fillColor: const Color(0xFF1A1A1A),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _sortChip(String label, String value) {
    bool isSelected = _sortBy == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          if (selected) setState(() => _sortBy = value);
        },
        selectedColor: Colors.blueAccent.withOpacity(0.2),
        backgroundColor: Colors.transparent,
        labelStyle: TextStyle(color: isSelected ? Colors.blueAccent : Colors.white24, fontSize: 12),
        shape: StadiumBorder(side: BorderSide(color: isSelected ? Colors.blueAccent : Colors.white10)),
      ),
    );
  }

  String _formatTaskTitle(String type) {
    if (type.toLowerCase() == 'scan_plant') return "Routine Scan";
    if (type.toLowerCase() == 'water') return "Task Completed: Watering";
    return type.toUpperCase();
  }

  String _getTaskDescription(String type, String status) {
    if (type.toLowerCase() == 'water') return "Dispensed 200ml of water. Soil moisture optimal.";
    if (type.toLowerCase() == 'scan_plant') return "Image scan complete. Plant growth at expected stage.";
    return "Robot successfully executed directive: $status.";
  }
}