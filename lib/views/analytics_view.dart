import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';

class AnalyticsView extends StatefulWidget {
  const AnalyticsView({super.key});

  @override
  State<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<AnalyticsView> {
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
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
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

      // --- THE FIX: We build the query chain in the correct order ---
      var query = Supabase.instance.client
          .from('readings')
          .select()
          .gte('recorded_at', startDate.toIso8601String());

      // 1. Apply Filters first
      if (_selectedLocation != 'All Locations') {
        query = query.eq('plant_location', _selectedLocation);
      }

      // 2. Apply Transforms (like order) last!
      final data = await query.order('recorded_at', ascending: true);
      
      // Update location filter list
      final allData = await Supabase.instance.client.from('readings').select('plant_location');
      final uniqueLocs = allData
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

  List<FlSpot> _generateSpots() {
    if (_readings.isEmpty) return [];
    List<FlSpot> spots = [];
    for (int i = 0; i < _readings.length; i++) {
      double val = 0;
      if (_readings[i]['water_stress_level'] != null) {
        val = double.parse(_readings[i]['water_stress_level'].toString());
      }
      spots.add(FlSpot(i.toDouble(), val));
    }
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    double avgStress = 0;
    int diseases = 0;

    if (_readings.isNotEmpty) {
      double total = 0;
      for (var r in _readings) {
        total += double.parse((r['water_stress_level'] ?? 0).toString());
        if (r['disease_detected'] == true) diseases++;
      }
      avgStress = total / _readings.length;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('System Analytics', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
              Row(
                children: [
                  _buildFilter(_selectedLocation, _availableLocations, Colors.greenAccent, (v) {
                    setState(() => _selectedLocation = v!);
                    _fetchData();
                  }),
                  const SizedBox(width: 16),
                  _buildFilter(_selectedTimeRange, ['Today', 'Last 7 Days', 'Last 30 Days', 'All Time'], Colors.blueAccent, (v) {
                    setState(() => _selectedTimeRange = v!);
                    _fetchData();
                  }),
                ],
              )
            ],
          ),
          const SizedBox(height: 40),

          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
          else if (_readings.isEmpty)
            const Center(child: Text('No telemetry data found.', style: TextStyle(color: Colors.white54, fontSize: 18)))
          else ...[
            Row(
              children: [
                Expanded(child: _card('Avg Water Stress', avgStress.toStringAsFixed(1), Icons.water_drop, Colors.blueAccent)),
                const SizedBox(width: 24),
                Expanded(child: _card('Diseases Detected', '$diseases', Icons.coronavirus, diseases > 0 ? Colors.redAccent : Colors.greenAccent)),
                const SizedBox(width: 24),
                Expanded(child: _card('Total Readings', '${_readings.length}', Icons.analytics, Colors.purpleAccent)),
              ],
            ),
            const SizedBox(height: 40),

            const Text('Water Stress Over Time', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            Container(
              height: 400,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white12)),
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  titlesData: const FlTitlesData(
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _generateSpots(),
                      isCurved: true,
                      color: Colors.blueAccent,
                      barWidth: 4,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(show: true, color: Colors.blueAccent.withOpacity(0.1)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),

            if (diseases > 0) ...[
              const Text('Recent Alerts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.redAccent)),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _readings.where((r) => r['disease_detected'] == true).length,
                  separatorBuilder: (c, i) => const Divider(color: Colors.white12, height: 1),
                  itemBuilder: (c, i) {
                    final alert = _readings.where((r) => r['disease_detected'] == true).toList()[i];
                    final dt = DateTime.parse(alert['recorded_at']).toLocal();
                    return ListTile(
                      leading: const Icon(Icons.warning, color: Colors.redAccent),
                      title: Text(alert['disease_name'] ?? 'Pathogen Detected', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: Text('Location: ${alert['plant_location']} • ${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}', style: const TextStyle(color: Colors.white54)),
                    );
                  },
                ),
              ),
              const SizedBox(height: 40),
            ]
          ]
        ],
      ),
    );
  }

  Widget _buildFilter(String val, List<String> items, Color color, Function(String?) fn) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          dropdownColor: const Color(0xFF1A1A1A),
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
          value: items.contains(val) ? val : items.first,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: fn,
        ),
      ),
    );
  }

  Widget _card(String title, String val, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, color: color, size: 20), const SizedBox(width: 8), Text(title, style: const TextStyle(color: Colors.white54))]),
          const SizedBox(height: 16),
          Text(val, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}