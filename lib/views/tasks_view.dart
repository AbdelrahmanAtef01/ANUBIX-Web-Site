import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TasksView extends StatefulWidget {
  const TasksView({super.key});

  @override
  State<TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends State<TasksView> {
  final _currentUser = Supabase.instance.client.auth.currentUser;
  late Stream<List<Map<String, dynamic>>> _profileStream;

  final _tasksStream = Supabase.instance.client
      .from('scheduled_tasks')
      .stream(primaryKey: ['task_id'])
      .order('scheduled_time', ascending: true);

  // --- PHYSICAL DISTANCE CACHE (For Logical <-> Physical Translation) ---
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

  // ==========================================
  // TRANSLATOR: UI (Logical 1,2) -> DB (Physical 30.0,50.0)
  // ==========================================
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

  // ==========================================
  // TRANSLATOR: DB (Physical 30.0,50.0) -> UI (Logical 1,2)
  // ==========================================
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

    final String initialLocation = isEditing
        ? existingTask['plant_location'] ?? ''
        : '';

    // --- REMOVED: typeController ---
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
              backgroundColor: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.white12),
              ),
              title: Row(
                children: [
                  Icon(
                    isEditing ? Icons.edit : Icons.schedule,
                    color: Colors.greenAccent,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isEditing ? 'Edit Directive' : 'Schedule Directive',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // --- REMOVED: Task Type TextField ---
                    TextField(
                      controller: locationController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Target Zone (Row, Col)',
                        hintText: 'e.g., 1,2',
                        labelStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: const Color(0xFF121212),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                            ),
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text(
                              selectedDate == null
                                  ? 'Set Date'
                                  : '${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}',
                            ),
                            onPressed: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: selectedDate ?? DateTime.now(),
                                firstDate: DateTime.now(),
                                lastDate: DateTime(2030),
                              );
                              if (date != null)
                                setState(() => selectedDate = date);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                            ),
                            icon: const Icon(Icons.access_time, size: 16),
                            label: Text(
                              selectedTime == null
                                  ? 'Set Time'
                                  : selectedTime!.format(context),
                            ),
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
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    final location = locationController.text.trim();

                    // --- MODIFIED: Removed type validation ---
                    if (location.isEmpty ||
                        selectedDate == null ||
                        selectedTime == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Please fill all fields and set a time.',
                          ),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }

                    // --- ADDED: Auto-assign task type behind the scenes ---
                    // final type = isEditing ? existingTask['task_type'] : 'disease';

                    // final physicalLocation = _logicalToPhysical(location);
                    final finalDateTime = DateTime(
                      selectedDate!.year,
                      selectedDate!.month,
                      selectedDate!.day,
                      selectedTime!.hour,
                      selectedTime!.minute,
                    );
                    final scheduledIsoString = finalDateTime
                        .toUtc()
                        .toIso8601String();

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
                            content: Text(
                              isEditing
                                  ? 'Directive Updated Successfully!'
                                  : 'Directive Scheduled Successfully!',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (error) {
                      debugPrint('DB Error: $error');
                    }
                  },
                  child: Text(
                    isEditing ? 'UPDATE' : 'SCHEDULE',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
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
                  const Text(
                    'Scheduled Directives',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent.withOpacity(0.2),
                      foregroundColor: Colors.greenAccent,
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('NEW SCHEDULE'),
                    onPressed: () => _showTaskDialog(context),
                  ),
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
                          color: Colors.greenAccent,
                        ),
                      );
                    }
                    final tasks = snapshot.data ?? [];
                    if (tasks.isEmpty) {
                      return const Center(
                        child: Text(
                          'No scheduled tasks. ANUBIX is on standby.',
                          style: TextStyle(color: Colors.white54, fontSize: 18),
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: tasks.length,
                      separatorBuilder: (context, index) =>
                          const Divider(color: Colors.white12, height: 1),
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        final isSent =
                            task['notification_sent'] as bool? ?? false;
                        final scheduledText = task['scheduled_time'] != null
                            ? "${DateTime.parse(task['scheduled_time']).toLocal().month}/${DateTime.parse(task['scheduled_time']).toLocal().day} at ${DateTime.parse(task['scheduled_time']).toLocal().hour}:${DateTime.parse(task['scheduled_time']).toLocal().minute.toString().padLeft(2, '0')}"
                            : "Pending";

                        final logicalLocUI =
                            task['plant_location'] ?? ''; //_physicalToLogical(
                        //   task['plant_location'] ?? '',
                        // );

                        return ListTile(
                          // LOCKED VISUAL INDICATOR - NO ONTAP
                          leading: Icon(
                            isSent
                                ? Icons.mark_email_read
                                : Icons.schedule_send,
                            color: isSent ? Colors.blueAccent : Colors.white54,
                            size: 28,
                          ),

                          title: Text(
                            "disease",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 14,
                                color: Colors.blueAccent,
                              ),
                              Text(
                                logicalLocUI,
                                style: const TextStyle(
                                  color: Colors.blueAccent,
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Icon(
                                Icons.access_time,
                                size: 14,
                                color: Colors.orangeAccent,
                              ),
                              Text(
                                scheduledText,
                                style: const TextStyle(
                                  color: Colors.orangeAccent,
                                ),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.white54,
                                ),
                                onPressed: () => _showTaskDialog(
                                  context,
                                  existingTask: task,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () => _deleteTask(task['task_id']),
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
