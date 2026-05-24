import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';

class ConfigView extends StatefulWidget {
  const ConfigView({super.key});

  @override
  State<ConfigView> createState() => _ConfigViewState();
}

class _ConfigViewState extends State<ConfigView> {
  final _currentUser = Supabase.instance.client.auth.currentUser;

  final _rowsController = TextEditingController();
  final _colsController = TextEditingController();
  final _distRowsController = TextEditingController();
  final _distColsController = TextEditingController();
  final _homeLocationController = TextEditingController();
  final _robotNameController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _robotId;
  String? _robotStatus;
  String? _robotCurrentLocation;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _rowsController.dispose();
    _colsController.dispose();
    _distRowsController.dispose();
    _distColsController.dispose();
    _homeLocationController.dispose();
    _robotNameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    if (_currentUser == null) return;
    setState(() => _isLoading = true);

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', _currentUser!.id)
          .single();

      _rowsController.text = (profile['grid_rows'] ?? 3).toString();
      _colsController.text = (profile['grid_columns'] ?? 3).toString();
      _distRowsController.text =
          (profile['distance_between_rows'] ?? '').toString();
      _distColsController.text =
          (profile['distance_between_columns'] ?? '').toString();
      _homeLocationController.text = profile['home_location'] ?? '0,0';
      _robotId = profile['robot_id'];

      if (_robotId != null) {
        final robot = await Supabase.instance.client
            .from('robots')
            .select()
            .eq('robot_id', _robotId!)
            .maybeSingle();

        if (robot != null) {
          _robotNameController.text = robot['name'] ?? '';
          _robotStatus = robot['status'];
          _robotCurrentLocation = robot['current_location'];
        }
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    if (_currentUser == null) return;
    setState(() => _isSaving = true);

    try {
      String? robotId = _robotId;

      if (robotId == null) {
        final robotName = _robotNameController.text.trim().isEmpty
            ? 'ANUBIX-Bot'
            : _robotNameController.text.trim();
        final newRobot = await Supabase.instance.client
            .from('robots')
            .insert({
              'name': robotName,
              'status': 'active',
              'current_location': _homeLocationController.text.trim(),
            })
            .select()
            .single();
        robotId = newRobot['robot_id'];
        _robotId = robotId;
        _robotStatus = 'active';
        _robotCurrentLocation = _homeLocationController.text.trim();
      } else {
        final robotName = _robotNameController.text.trim();
        if (robotName.isNotEmpty) {
          await Supabase.instance.client
              .from('robots')
              .update({'name': robotName}).eq('robot_id', robotId);
        }
      }

      final distRows = double.tryParse(_distRowsController.text.trim());
      final distCols = double.tryParse(_distColsController.text.trim());

      await Supabase.instance.client.from('profiles').update({
        'grid_rows': int.tryParse(_rowsController.text.trim()) ?? 3,
        'grid_columns': int.tryParse(_colsController.text.trim()) ?? 3,
        'distance_between_rows': distRows,
        'distance_between_columns': distCols,
        'home_location': _homeLocationController.text.trim(),
        'robot_id': robotId,
      }).eq('id', _currentUser!.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Configuration saved successfully.'),
          backgroundColor: AppColors.healthy,
        ));
      }
    } catch (e) {
      debugPrint('Error saving profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: AppColors.diseased,
        ));
      }
    }

    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Center(
          child: Text('Authentication required.',
              style: TextStyle(color: AppColors.textPrimary)));
    }

    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.orange));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Configuration',
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          letterSpacing: 1.2)),
                  SizedBox(height: 4),
                  Text('Farm grid layout, distances & robot settings',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 14)),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, size: 18),
                label: Text(_isSaving ? 'SAVING...' : 'SAVE',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ],
          ),
          const SizedBox(height: 40),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildGridSection()),
              const SizedBox(width: 24),
              Expanded(child: _buildDistanceSection()),
            ],
          ),
          const SizedBox(height: 24),
          _buildRobotSection(),
        ],
      ),
    );
  }

  Widget _buildGridSection() {
    return _sectionCard(
      title: 'Grid Layout',
      icon: Icons.grid_view_rounded,
      children: [
        _buildField(
          label: 'Rows',
          controller: _rowsController,
          hint: '3',
          icon: Icons.table_rows_rounded,
          isInt: true,
        ),
        const SizedBox(height: 20),
        _buildField(
          label: 'Columns',
          controller: _colsController,
          hint: '3',
          icon: Icons.view_column_rounded,
          isInt: true,
        ),
        const SizedBox(height: 20),
        _buildField(
          label: 'Home Location',
          controller: _homeLocationController,
          hint: '0,0',
          icon: Icons.home_rounded,
        ),
      ],
    );
  }

  Widget _buildDistanceSection() {
    return _sectionCard(
      title: 'Spacing (cm)',
      icon: Icons.straighten_rounded,
      children: [
        _buildField(
          label: 'Distance Between Rows',
          controller: _distRowsController,
          hint: '10',
          icon: Icons.swap_vert_rounded,
          isDecimal: true,
        ),
        const SizedBox(height: 20),
        _buildField(
          label: 'Distance Between Columns',
          controller: _distColsController,
          hint: '10',
          icon: Icons.swap_horiz_rounded,
          isDecimal: true,
        ),
      ],
    );
  }

  Widget _buildRobotSection() {
    return _sectionCard(
      title: 'Robot',
      icon: Icons.precision_manufacturing_rounded,
      trailing: _robotId == null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.unknown.withAlpha(30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('No robot linked — one will be created on save',
                  style: TextStyle(
                      color: AppColors.unknown,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.healthy.withAlpha(30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                        color: AppColors.healthy, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(_robotStatus ?? 'active',
                    style: const TextStyle(
                        color: AppColors.healthy,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
      children: [
        _buildField(
          label: 'Robot Name',
          controller: _robotNameController,
          hint: 'ANUBIX-Bot',
          icon: Icons.smart_toy_rounded,
        ),
        if (_robotId != null) ...[
          const SizedBox(height: 16),
          Row(children: [
            _infoChip(Icons.fingerprint, 'ID', _robotId!.substring(0, 8)),
            const SizedBox(width: 12),
            _infoChip(
              Icons.location_on_outlined,
              'Location',
              _robotCurrentLocation ?? 'N/A',
            ),
          ]),
        ],
      ],
    );
  }

  Widget _infoChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgPrimary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: AppColors.textMuted, size: 14),
        const SizedBox(width: 6),
        Text('$label: ',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        Text(value,
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(28),
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
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.orange.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppColors.orange, size: 18),
            ),
            const SizedBox(width: 12),
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            if (trailing != null) ...[const Spacer(), trailing],
          ]),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isInt = false,
    bool isDecimal = false,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: AppColors.textPrimary),
      keyboardType: isInt
          ? TextInputType.number
          : isDecimal
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
      inputFormatters: isInt
          ? [FilteringTextInputFormatter.digitsOnly]
          : isDecimal
              ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))]
              : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        hintStyle:
            TextStyle(color: AppColors.textMuted.withAlpha(120), fontSize: 13),
        filled: true,
        fillColor: AppColors.bgPrimary,
        prefixIcon: Icon(icon, color: AppColors.textMuted, size: 18),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.orange, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
