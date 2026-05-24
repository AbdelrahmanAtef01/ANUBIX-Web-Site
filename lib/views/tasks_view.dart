import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';

class TasksView extends StatefulWidget {
  const TasksView({super.key});

  @override
  State<TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends State<TasksView> {
  final _currentUser = Supabase.instance.client.auth.currentUser;
  late Stream<List<Map<String, dynamic>>> _profileStream;

  bool _ascending = false;

  Stream<List<Map<String, dynamic>>> get _tasksStream =>
      Supabase.instance.client
          .from('scheduled_tasks')
          .stream(primaryKey: ['task_id'])
          .order('scheduled_time', ascending: _ascending);

  double _cachedDistRows = 10.0;
  double _cachedDistCols = 10.0;

  @override
  void initState() {
    super.initState();
    _profileStream = Supabase.instance.client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', _currentUser?.id ?? '')
        .limit(1);
  }

  String _logicalToPhysical(String loc) {
    try {
      final matches = RegExp(r'\d+').allMatches(loc);
      if (matches.length >= 2) {
        final r = int.parse(matches.elementAt(0).group(0)!);
        final c = int.parse(matches.elementAt(1).group(0)!);
        return '${r * _cachedDistRows},${c * _cachedDistCols}';
      }
    } catch (_) {}
    return loc;
  }

  String _physicalToLogical(String loc) {
    try {
      final parts = loc.split(',');
      if (parts.length >= 2) {
        final x = double.parse(parts[0].trim());
        final y = double.parse(parts[1].trim());
        final r = (x / (_cachedDistRows > 0 ? _cachedDistRows : 1)).round();
        final c = (y / (_cachedDistCols > 0 ? _cachedDistCols : 1)).round();
        return '$r,$c';
      }
    } catch (_) {}
    return loc;
  }

  Future<String?> _getRobotId() async {
    try {
      final response = await Supabase.instance.client
          .from('robots')
          .select('robot_id')
          .limit(1)
          .single();
      return response['robot_id'] as String;
    } catch (e) {
      debugPrint('No robot found: $e');
      return null;
    }
  }

  Future<void> _showTaskDialog(
    BuildContext context, {
    Map<String, dynamic>? existingTask,
  }) async {
    final isEditing = existingTask != null;
    final String initialLocation =
        isEditing ? existingTask['plant_location'] ?? '' : '';
    final locationController = TextEditingController(text: initialLocation);

    DateTime? selectedDate;
    TimeOfDay? selectedTime;

    if (isEditing && existingTask['scheduled_time'] != null) {
      final dt = DateTime.parse(existingTask['scheduled_time']).toLocal();
      selectedDate = dt;
      selectedTime = TimeOfDay.fromDateTime(dt);
    }

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: AppColors.bgSecondary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.border),
              ),
              title: Row(children: [
                Icon(isEditing ? Icons.edit : Icons.schedule,
                    color: AppColors.orange),
                const SizedBox(width: 10),
                Text(isEditing ? 'Edit Directive' : 'Schedule Directive',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold)),
              ]),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: locationController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Target Zone (Row, Col)',
                        hintText: 'e.g., 1,2',
                        labelStyle:
                            const TextStyle(color: AppColors.textMuted),
                        filled: true,
                        fillColor: AppColors.bgPrimary,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textSecondary),
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(selectedDate == null
                              ? 'Set Date'
                              : '${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}'),
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: selectedDate ?? DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime(2030),
                            );
                            if (date != null) {
                              setState(() => selectedDate = date);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textSecondary),
                          icon: const Icon(Icons.access_time, size: 16),
                          label: Text(selectedTime == null
                              ? 'Set Time'
                              : selectedTime!.format(context)),
                          onPressed: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: selectedTime ?? TimeOfDay.now(),
                            );
                            if (time != null) {
                              setState(() => selectedTime = time);
                            }
                          },
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('CANCEL',
                      style: TextStyle(color: AppColors.textMuted)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final location = locationController.text.trim();
                    if (location.isEmpty ||
                        selectedDate == null ||
                        selectedTime == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Please fill all fields and set a time.'),
                          backgroundColor: AppColors.unknown,
                        ),
                      );
                      return;
                    }

                    final finalDateTime = DateTime(
                      selectedDate!.year,
                      selectedDate!.month,
                      selectedDate!.day,
                      selectedTime!.hour,
                      selectedTime!.minute,
                    );
                    final scheduledIsoString =
                        finalDateTime.toUtc().toIso8601String();

                    try {
                      if (isEditing) {
                        await Supabase.instance.client
                            .from('scheduled_tasks')
                            .update({
                              'plant_location': location,
                              'scheduled_time': scheduledIsoString,
                              'notification_sent': false,
                            })
                            .eq('task_id', existingTask['task_id']);
                      } else {
                        final robotId = await _getRobotId();
                        await Supabase.instance.client
                            .from('scheduled_tasks')
                            .insert({
                          'user_id': _currentUser?.id,
                          'robot_id': robotId,
                          'plant_location': location,
                          'scheduled_time': scheduledIsoString,
                          'notification_sent': false,
                        });
                      }
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(isEditing
                                ? 'Directive Updated Successfully!'
                                : 'Directive Scheduled Successfully!'),
                            backgroundColor: AppColors.healthy,
                          ),
                        );
                      }
                    } catch (error) {
                      debugPrint('DB Error: $error');
                    }
                  },
                  child: Text(isEditing ? 'UPDATE' : 'SCHEDULE',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteTask(String id) async => await Supabase.instance.client
      .from('scheduled_tasks')
      .delete()
      .eq('task_id', id);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _profileStream,
      builder: (context, profileSnapshot) {
        if (profileSnapshot.hasData && profileSnapshot.data!.isNotEmpty) {
          final profile = profileSnapshot.data!.first;
          _cachedDistRows =
              (profile['distance_between_rows'] as num?)?.toDouble() ?? 10.0;
          _cachedDistCols =
              (profile['distance_between_columns'] as num?)?.toDouble() ??
                  _cachedDistRows;
        }

        return Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Scheduled Directives',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary)),
                  Row(children: [
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _ascending = !_ascending),
                      icon: Icon(
                          _ascending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 16),
                      label:
                          Text(_ascending ? "Oldest First" : "Newest First"),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.accent),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.orange.withAlpha(40),
                        foregroundColor: AppColors.orange,
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('NEW SCHEDULE'),
                      onPressed: () => _showTaskDialog(context),
                    ),
                  ]),
                ],
              ),
              const SizedBox(height: 30),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _tasksStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.orange));
                    }
                    final tasks = snapshot.data ?? [];
                    if (tasks.isEmpty) {
                      return const Center(
                        child: Text(
                            'No scheduled tasks. ANUBIX is on standby.',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 18)),
                      );
                    }

                    return ListView.separated(
                      itemCount: tasks.length,
                      separatorBuilder: (context, index) =>
                          const Divider(color: AppColors.border, height: 1),
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        final isSent =
                            task['notification_sent'] as bool? ?? false;
                        final scheduledText = task['scheduled_time'] != null
                            ? "${DateTime.parse(task['scheduled_time']).toLocal().month}/${DateTime.parse(task['scheduled_time']).toLocal().day} at ${DateTime.parse(task['scheduled_time']).toLocal().hour}:${DateTime.parse(task['scheduled_time']).toLocal().minute.toString().padLeft(2, '0')}"
                            : "Pending";

                        final logicalLocUI = task['plant_location'] ?? '';

                        return ListTile(
                          leading: Icon(
                            isSent
                                ? Icons.mark_email_read
                                : Icons.schedule_send,
                            color:
                                isSent ? AppColors.accent : AppColors.textMuted,
                            size: 28,
                          ),
                          title: const Text("Disease Detection",
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold)),
                          subtitle: Row(children: [
                            const Icon(Icons.location_on,
                                size: 14, color: AppColors.accent),
                            Text(logicalLocUI,
                                style:
                                    const TextStyle(color: AppColors.accent)),
                            const SizedBox(width: 16),
                            const Icon(Icons.access_time,
                                size: 14, color: AppColors.orange),
                            Text(scheduledText,
                                style: const TextStyle(
                                    color: AppColors.orange)),
                          ]),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit,
                                    color: AppColors.textMuted),
                                onPressed: () => _showTaskDialog(context,
                                    existingTask: task),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    color: AppColors.diseased),
                                onPressed: () =>
                                    _deleteTask(task['task_id']),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
