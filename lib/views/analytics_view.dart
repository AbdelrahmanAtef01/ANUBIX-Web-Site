import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme.dart';

class AnalyticsView extends StatefulWidget {
  const AnalyticsView({super.key});

  @override
  State<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<AnalyticsView> {
  final _currentUser = Supabase.instance.client.auth.currentUser;
  List<Map<String, dynamic>> _readings = [];
  bool _isLoading = true;

  String _selectedLocation = 'All Locations';
  String _selectedTimeRange = 'Last 7 Days';
  List<String> _availableLocations = ['All Locations'];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (!mounted || _currentUser == null) return;
    setState(() => _isLoading = true);

    try {
      final taskData = await Supabase.instance.client
          .from('task_history')
          .select('task_id')
          .eq('user_id', _currentUser!.id);

      final taskIds =
          taskData.map((t) => t['task_id'] as String).toList();

      if (taskIds.isEmpty) {
        if (mounted) {
          setState(() {
            _readings = [];
            _availableLocations = ['All Locations'];
            _isLoading = false;
          });
        }
        return;
      }

      DateTime now = DateTime.now().toUtc();
      DateTime startDate;

      if (_selectedTimeRange == 'Today') {
        startDate = now.subtract(const Duration(days: 1));
      } else if (_selectedTimeRange == 'Last 7 Days') {
        startDate = now.subtract(const Duration(days: 7));
      } else if (_selectedTimeRange == 'Last 30 Days') {
        startDate = now.subtract(const Duration(days: 30));
      } else {
        startDate = now.subtract(const Duration(days: 3650));
      }

      var query = Supabase.instance.client
          .from('readings')
          .select()
          .inFilter('task_id', taskIds)
          .gte('recorded_at', startDate.toIso8601String());

      if (_selectedLocation != 'All Locations') {
        query = query.eq('plant_location', _selectedLocation);
      }

      final data = await query.order('recorded_at', ascending: true);

      final allUserReadings = await Supabase.instance.client
          .from('readings')
          .select('plant_location')
          .inFilter('task_id', taskIds);
      final uniqueLocs = allUserReadings
          .where((e) => e['plant_location'] != null)
          .map((e) => e['plant_location'] as String)
          .toSet()
          .toList();

      if (mounted) {
        setState(() {
          _readings = List<Map<String, dynamic>>.from(data);
          _availableLocations = ['All Locations', ...uniqueLocs];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Analytics Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    int totalReadings = _readings.length;
    int diseases = 0;

    for (var r in _readings) {
      if (r['disease_detected'] == true) diseases++;
    }

    int healthy = totalReadings - diseases;
    double healthRate =
        totalReadings == 0 ? 0 : (healthy / totalReadings) * 100;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('System Analytics',
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          letterSpacing: 1.2)),
                  SizedBox(height: 4),
                  Text('Real-time agricultural telemetry & health tracking',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 14)),
                ],
              ),
              Row(children: [
                _buildFilter(
                  _selectedLocation,
                  _availableLocations,
                  AppColors.orange,
                  (v) {
                    setState(() => _selectedLocation = v!);
                    _fetchData();
                  },
                ),
                const SizedBox(width: 16),
                _buildFilter(
                  _selectedTimeRange,
                  ['Today', 'Last 7 Days', 'Last 30 Days', 'All Time'],
                  AppColors.accent,
                  (v) {
                    setState(() => _selectedTimeRange = v!);
                    _fetchData();
                  },
                ),
              ]),
            ],
          ),
          const SizedBox(height: 40),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 100),
              child: Center(
                  child: CircularProgressIndicator(
                      color: AppColors.orange, strokeWidth: 2)),
            )
          else if (_readings.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 100),
              child: Center(
                  child: Text('No telemetry data found for this period.',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 18,
                          letterSpacing: 1))),
            )
          else ...[
            Row(children: [
              Expanded(
                  child: _buildMetricCard(
                      'Total Scans', '$totalReadings', Icons.radar,
                      AppColors.accent)),
              const SizedBox(width: 24),
              Expanded(
                  child: _buildMetricCard(
                      'Healthy Crops', '$healthy', Icons.eco,
                      AppColors.healthy)),
              const SizedBox(width: 24),
              Expanded(
                  child: _buildMetricCard(
                      'Alerts',
                      '$diseases',
                      Icons.coronavirus,
                      diseases > 0 ? AppColors.diseased : AppColors.textMuted)),
            ]),
            const SizedBox(height: 40),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Container(
                    height: 380,
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: AppColors.bgSecondary,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withAlpha(40),
                            blurRadius: 10,
                            offset: const Offset(0, 5)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Crop Health Distribution',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 8),
                        Text(
                            'Overall Health Rate: ${healthRate.toStringAsFixed(1)}%',
                            style: TextStyle(
                                color: healthRate > 80
                                    ? AppColors.healthy
                                    : AppColors.orange,
                                fontSize: 14)),
                        const SizedBox(height: 30),
                        Expanded(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              PieChart(
                                PieChartData(
                                  sectionsSpace: 4,
                                  centerSpaceRadius: 70,
                                  startDegreeOffset: -90,
                                  sections: [
                                    if (healthy > 0)
                                      PieChartSectionData(
                                        color: AppColors.healthy.withAlpha(200),
                                        value: healthy.toDouble(),
                                        title:
                                            '${((healthy / totalReadings) * 100).toStringAsFixed(0)}%',
                                        radius: 40,
                                        titleStyle: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white),
                                      ),
                                    if (diseases > 0)
                                      PieChartSectionData(
                                        color:
                                            AppColors.diseased.withAlpha(200),
                                        value: diseases.toDouble(),
                                        title:
                                            '${((diseases / totalReadings) * 100).toStringAsFixed(0)}%',
                                        radius: 45,
                                        titleStyle: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white),
                                      ),
                                  ],
                                ),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.monitor_heart,
                                      color: AppColors.textMuted.withAlpha(120),
                                      size: 30),
                                  const SizedBox(height: 4),
                                  const Text('Status',
                                      style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 12)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 3,
                  child: Container(
                    height: 380,
                    decoration: BoxDecoration(
                      color: AppColors.bgSecondary,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withAlpha(40),
                            blurRadius: 10,
                            offset: const Offset(0, 5)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Recent Alerts',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary)),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.diseased.withAlpha(30),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text('$diseases Active',
                                    style: const TextStyle(
                                        color: AppColors.diseased,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: diseases == 0
                              ? const Center(
                                  child: Text(
                                      'No recent diseases detected. Crops are healthy!',
                                      style: TextStyle(
                                          color: AppColors.healthy,
                                          fontSize: 16)))
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  itemCount: _readings
                                      .where(
                                          (r) => r['disease_detected'] == true)
                                      .length,
                                  itemBuilder: (context, index) {
                                    final alert = _readings
                                        .where((r) =>
                                            r['disease_detected'] == true)
                                        .toList()[index];
                                    final dt = DateTime.parse(
                                            alert['recorded_at'])
                                        .toLocal();
                                    return Container(
                                      margin:
                                          const EdgeInsets.only(bottom: 12),
                                      decoration: BoxDecoration(
                                        color:
                                            AppColors.diseased.withAlpha(12),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        border: Border.all(
                                            color: AppColors.diseased
                                                .withAlpha(40)),
                                      ),
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 20, vertical: 8),
                                        leading: Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: AppColors.diseased
                                                .withAlpha(30),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.bug_report,
                                              color: AppColors.diseased,
                                              size: 20),
                                        ),
                                        title: Text(
                                            alert['disease_name'] ??
                                                'Unknown Pathogen',
                                            style: const TextStyle(
                                                color: AppColors.textPrimary,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16)),
                                        subtitle: Padding(
                                          padding:
                                              const EdgeInsets.only(top: 6.0),
                                          child: Text(
                                              'Zone: ${alert['plant_location']}',
                                              style: const TextStyle(
                                                  color:
                                                      AppColors.textSecondary,
                                                  fontSize: 13)),
                                        ),
                                        trailing: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text('${dt.month}/${dt.day}',
                                                style: const TextStyle(
                                                    color:
                                                        AppColors.textMuted,
                                                    fontSize: 12)),
                                            const SizedBox(height: 4),
                                            Text(
                                                '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}',
                                                style: const TextStyle(
                                                    color:
                                                        AppColors.textMuted,
                                                    fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ],
      ),
    );
  }

  Widget _buildFilter(
    String val,
    List<String> items,
    Color accentColor,
    Function(String?) fn,
  ) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          dropdownColor: AppColors.bgCard,
          icon:
              Icon(Icons.keyboard_arrow_down, color: accentColor, size: 18),
          style: TextStyle(
              color: accentColor, fontWeight: FontWeight.w600, fontSize: 13),
          value: items.contains(val) ? val : items.first,
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: fn,
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String val,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(30),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(val,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 36,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(color: color.withAlpha(80), blurRadius: 10)],
              )),
        ],
      ),
    );
  }
}
