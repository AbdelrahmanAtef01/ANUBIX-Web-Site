import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../theme.dart';

class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  String _sortBy = "execution_time";
  bool _ascending = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('System Command Log',
              style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 20),
          Row(children: [
            const Text('Sort by:',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(width: 10),
            _sortChip('Date', 'execution_time'),
            _sortChip('Location', 'plant_location'),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => _ascending = !_ascending),
              icon: Icon(
                  _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 16),
              label: Text(_ascending ? "Oldest First" : "Newest First"),
              style: TextButton.styleFrom(foregroundColor: AppColors.accent),
            ),
          ]),
          const SizedBox(height: 30),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client
                  .from('task_history')
                  .stream(primaryKey: ['task_id'])
                  .order(_sortBy, ascending: _ascending),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.orange));
                }

                final logs = snapshot.data ?? [];

                if (logs.isEmpty) {
                  return const Center(
                      child: Text("No records found in command history.",
                          style: TextStyle(color: AppColors.textMuted)));
                }

                return ListView.separated(
                  itemCount: logs.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 16),
                  itemBuilder: (context, index) => _buildLogItem(logs[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogItem(Map<String, dynamic> log) {
    final taskId = log['task_id']?.toString() ?? '';
    final location = log['plant_location'] ?? 'N/A';
    final status = log['status'] ?? 'Completed';
    final time = DateTime.parse(log['execution_time']).toLocal();
    final timeStr = DateFormat('MMM d, hh:mm a').format(time);

    return FutureBuilder<Map<String, dynamic>?>(
      future: Supabase.instance.client
          .from('readings')
          .select('disease_detected')
          .eq('task_id', taskId)
          .order('recorded_at', ascending: false)
          .limit(1)
          .maybeSingle(),
      builder: (context, snapshot) {
        String titleText = "Diagnosis: Unknown";
        Color itemColor = AppColors.unknown;
        IconData itemIcon = Icons.warning_amber_rounded;

        if (snapshot.connectionState == ConnectionState.waiting) {
          titleText = "Diagnosis: Checking...";
          itemColor = AppColors.textMuted;
          itemIcon = Icons.hourglass_empty;
        } else if (snapshot.hasData && snapshot.data != null) {
          final isDiseased = snapshot.data!['disease_detected'];
          if (isDiseased == true) {
            titleText = "Diagnosis: Diseased";
            itemColor = AppColors.diseased;
            itemIcon = Icons.warning_amber_rounded;
          } else if (isDiseased == false) {
            titleText = "Diagnosis: Normal";
            itemColor = AppColors.healthy;
            itemIcon = Icons.check_circle_outline;
          }
        }

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.bgSecondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: itemColor.withAlpha(25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: itemColor.withAlpha(25),
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
                        Text(titleText,
                            style: TextStyle(
                                color: itemColor,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        Text(timeStr,
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_getTaskDescription(status),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 14)),
                    const SizedBox(height: 12),
                    Row(children: [
                      const Icon(Icons.location_on_outlined,
                          size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text("Location: ($location)",
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
        selectedColor: AppColors.accent.withAlpha(40),
        backgroundColor: Colors.transparent,
        labelStyle: TextStyle(
          color: isSelected ? AppColors.accent : AppColors.textMuted,
          fontSize: 12,
        ),
        shape: StadiumBorder(
          side: BorderSide(
            color: isSelected ? AppColors.accent : AppColors.border,
          ),
        ),
      ),
    );
  }

  String _getTaskDescription(String status) {
    return "Current task status: $status.";
  }
}
