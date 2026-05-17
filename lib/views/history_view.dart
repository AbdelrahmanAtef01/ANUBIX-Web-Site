import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  String _searchQuery = "";
  String _sortBy = "execution_time"; // Default sort
  bool _ascending = false; // Newest first

  // DELETED: _getIconForTask() - Logic moved into FutureBuilder
  // DELETED: _getColorForTask() - Logic moved into FutureBuilder

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
              const Text(
                'System Command Log',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              _buildSearchBar(),
            ],
          ),
          const SizedBox(height: 20),

          // --- SORTING CHIPS ---
          Row(
            children: [
              const Text(
                'Sort by:',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(width: 10),
              _sortChip('Date', 'execution_time'),
              _sortChip('Location', 'plant_location'),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _ascending = !_ascending),
                icon: Icon(
                  _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 16,
                ),
                label: Text(_ascending ? "Oldest First" : "Newest First"),
                style: TextButton.styleFrom(foregroundColor: Colors.blueAccent),
              ),
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
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                var logs = snapshot.data ?? [];

                // Client-side search filtering
                if (_searchQuery.isNotEmpty) {
                  logs =
                      logs
                          .where(
                            (l) =>
                                l['task_type']
                                    .toString()
                                    .toLowerCase()
                                    .contains(_searchQuery.toLowerCase()) ||
                                l['plant_location'].toString().contains(
                                  _searchQuery,
                                ),
                          )
                          .toList();
                }

                if (logs.isEmpty) {
                  return const Center(
                    child: Text("No records found in command history."),
                  );
                }

                return ListView.separated(
                  itemCount: logs.length,
                  separatorBuilder:
                      (context, index) => const SizedBox(height: 16),
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

  // --- LOG ITEM UI ---
  Widget _buildLogItem(Map<String, dynamic> log) {
    final type = 'disease';
    final taskId = log['task_id']?.toString() ?? '';
    final location = log['plant_location'] ?? 'N/A';
    final status = log['status'] ?? 'Completed';
    final time = DateTime.parse(log['execution_time']).toLocal();
    final timeStr = DateFormat('MMM d, hh:mm a').format(time);

    // MODIFIED: The FutureBuilder now wraps the entire Container
    // so it can dynamically update the border colors and icons.
    return FutureBuilder<Map<String, dynamic>?>(
      future:
          Supabase.instance.client
              .from('readings')
              .select('disease_detected')
              .eq('task_id', taskId)
              .order('recorded_at', ascending: false)
              .limit(1)
              .maybeSingle(),
      builder: (context, snapshot) {
        // ADDED: Default fallback states (Unknown Diagnosis)
        String titleText = "Diagnosis: Unknown";
        Color itemColor = Colors.amberAccent; // Yellow for unknown
        IconData itemIcon = Icons.warning_amber_rounded; // Warning for unknown

        // ADDED: Intermediate loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          titleText = "Diagnosis: Checking...";
          itemColor = Colors.white54;
          itemIcon = Icons.hourglass_empty;
        }
        // ADDED: Logic to parse the boolean and set colors/icons
        else if (snapshot.hasData && snapshot.data != null) {
          final isDiseased = snapshot.data!['disease_detected'];

          if (isDiseased == true) {
            titleText = "Diagnosis: Diseased";
            itemColor = Colors.redAccent;
            itemIcon = Icons.warning_amber_rounded;
          } else if (isDiseased == false) {
            titleText = "Diagnosis: Normal";
            itemColor = Colors.greenAccent;
            itemIcon = Icons.check_circle_outline; // Correct icon for normal
          } else {
            // If no reading exists for this task_id, it stays Unknown!
            titleText = "Diagnosis: Unknown";
            itemColor = Colors.amberAccent;
            itemIcon = Icons.warning_amber_rounded;
          }
          // If isDiseased is exactly null, it safely defaults to the Yellow/Unknown state above.
        }

        // Return the full UI block, injecting the dynamic variables
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: itemColor.withOpacity(0.1)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: itemColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(itemIcon, color: itemColor, size: 24),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          titleText,
                          style: TextStyle(
                            color: itemColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            color: Colors.white24,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getTaskDescription(type, status),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: Colors.white24,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "Location: ($location)",
                          style: const TextStyle(
                            color: Colors.white24,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(25),
            borderSide: BorderSide.none,
          ),
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
        labelStyle: TextStyle(
          color: isSelected ? Colors.blueAccent : Colors.white24,
          fontSize: 12,
        ),
        shape: StadiumBorder(
          side: BorderSide(
            color: isSelected ? Colors.blueAccent : Colors.white10,
          ),
        ),
      ),
    );
  }

  String _getTaskDescription(String type, String status) {
    return "Current task status: $status.";
  }
}
