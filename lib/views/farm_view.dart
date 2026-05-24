import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../theme.dart';

class _FieldOverlayPainter extends CustomPainter {
  final int rows;
  final int cols;
  final double cellW;
  final double cellH;
  final double gapW;
  final int? selRow;
  final int? selCol;

  const _FieldOverlayPainter({
    required this.rows,
    required this.cols,
    required this.cellW,
    required this.cellH,
    required this.gapW,
    this.selRow,
    this.selCol,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int vr = 0; vr < rows; vr++) {
      final rowTop = vr * (cellH + gapW) + gapW;
      if (vr % 2 == 0) {
        canvas.drawRect(
          Rect.fromLTWH(0, rowTop, size.width, cellH),
          Paint()..color = const Color(0xFF5C4228).withAlpha(22),
        );
      }
    }

    if (selRow != null && selCol != null && selRow! > 0) {
      final vr = rows - selRow!;
      final cellLeft = selCol! * gapW + (selCol! - 1) * cellW;
      final cellTop = vr * (cellH + gapW) + gapW;
      final cellRect = Rect.fromLTWH(cellLeft, cellTop, cellW, cellH);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
            cellRect.inflate(6), const Radius.circular(10)),
        Paint()
          ..shader = RadialGradient(
            colors: [AppColors.orange.withAlpha(45), Colors.transparent],
            radius: 0.85,
          ).createShader(cellRect.inflate(8)),
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(cellRect, const Radius.circular(6)),
        Paint()
          ..color = AppColors.orange.withAlpha(110)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }

    final homeTop = rows * (cellH + gapW) + gapW;
    final padRect = Rect.fromLTWH(gapW, homeTop, cellW, cellH);

    canvas.drawRRect(
      RRect.fromRectAndRadius(padRect, const Radius.circular(8)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF37474F).withAlpha(140),
            const Color(0xFF263238).withAlpha(120),
          ],
        ).createShader(padRect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(padRect, const Radius.circular(8)),
      Paint()
        ..color = AppColors.orange.withAlpha(90)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_FieldOverlayPainter old) =>
      old.selRow != selRow ||
      old.selCol != selCol ||
      old.rows != rows ||
      old.cols != cols ||
      old.cellW != cellW ||
      old.cellH != cellH;
}

class FarmView extends StatefulWidget {
  const FarmView({super.key});

  @override
  State<FarmView> createState() => _FarmViewState();
}

class _FarmViewState extends State<FarmView> {
  final _currentUser = Supabase.instance.client.auth.currentUser;
  final String robotAsset = 'assets/images/robot.png';

  late Stream<List<Map<String, dynamic>>> _profileStream;
  StreamSubscription<List<Map<String, dynamic>>>? _robotSubscription;
  final TextEditingController _chatController = TextEditingController();

  final List<Map<String, String>> _chatMessages = [];
  bool _isWaitingForAgent = false;
  final ScrollController _scrollController = ScrollController();

  double _cellW = 140.0;
  double _cellH = 80.0;
  double _pathW = 28.0;
  double _robotSz = 36.0;

  int _cachedRows = 4;

  double? _robotLeft;
  double? _robotTop;
  int _currentRow = 0;
  int _currentCol = 1;
  bool _isInitialLoad = true;
  bool _isDriving = false;
  int _animationSpeed = 1200;
  String? _activeRobotId;
  String? _selectedPlantZone;
  int? _selectedRow;
  int? _selectedCol;
  Timer? _hoverTimer;

  late String _currentSessionId;
  RealtimeChannel? _consoleSubscription;

  double _cachedDistRows = 10.0;
  double _cachedDistCols = 10.0;

  void _computeLayout(int rows, int cols, double availW, double availH) {
    if (rows <= 0 || cols <= 0 || availW <= 0 || availH <= 0) return;

    const rW = 7.0;
    const rH = 3.5;
    const rP = 1.2;

    final unitsW = cols * rW + (cols + 1) * rP;
    final unitsH = (rows + 1) * rH + (rows + 2) * rP;

    final unit = math.min(availW / unitsW, availH / unitsH);

    _cellW = rW * unit;
    _cellH = rH * unit;
    _pathW = rP * unit;
    _robotSz = math.max(24.0, math.min(_pathW * 3.0, _cellH * 1.1));

    if (_robotLeft != null && !_isDriving) {
      _robotLeft = _pathCenterX(_currentCol);
      _robotTop = _rowCenterY(_currentRow);
      _animationSpeed = 0;
    }
  }

  double _pathCenterX(int col) {
    if (col <= 0) col = 1;
    final pathStart = col * _pathW + col * _cellW;
    return pathStart + _pathW / 2 - _robotSz / 2;
  }

  double _rowCenterY(int row) {
    if (row <= 0) {
      final homeTop = _cachedRows * (_cellH + _pathW) + _pathW;
      return homeTop + _cellH / 2 - _robotSz / 2;
    }
    final visualRow = _cachedRows - row;
    final rowTop = visualRow * (_cellH + _pathW) + _pathW;
    return rowTop + _cellH / 2 - _robotSz / 2;
  }

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    _currentSessionId =
        'ANUBIX - ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';

    _listenForAutomatedBackendTasks();

    _profileStream = Supabase.instance.client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', _currentUser?.id ?? '')
        .limit(1);

    _robotSubscription = Supabase.instance.client
        .from('robots')
        .stream(primaryKey: ['robot_id'])
        .listen((data) {
      if (data.isNotEmpty) {
        final robot = data.first;
        _activeRobotId = robot['robot_id'];
        if (robot['current_location'] != null) {
          final parts = robot['current_location'].toString().split(',');
          if (parts.length == 2) {
            int tRow = int.tryParse(parts[0].trim()) ?? 0;
            int tCol = int.tryParse(parts[1].trim()) ?? 1;
            if (tRow < 0) tRow = 0;
            if (tCol < 1) tCol = 1;
            _driveRobotTo(tRow, tCol);
          }
        }
      }
    });
  }

  void _listenForAutomatedBackendTasks() {
    _consoleSubscription = Supabase.instance.client
        .channel('farm_view_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chats',
          callback: (payload) {
            debugPrint('[FARM] ${payload.newRecord['sender']}: '
                '${payload.newRecord['message']}');
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_consoleSubscription != null) {
      Supabase.instance.client.removeChannel(_consoleSubscription!);
    }
    _robotSubscription?.cancel();
    _hoverTimer?.cancel();
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessageToAgent() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _currentUser == null) return;
    if (_selectedRow == null || _selectedCol == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select a crop zone before sending a command.'),
        backgroundColor: AppColors.orange,
      ));
      return;
    }

    setState(() {
      _chatMessages.add({'role': 'user', 'text': text});
      _isWaitingForAgent = true;
    });
    _chatController.clear();
    _scrollToBottom();

    final realX = _selectedRow! * _cachedDistRows;
    final realY = _selectedCol! * _cachedDistCols;
    final taskId = const Uuid().v4();
    final sysCtx =
        'plant location at x= $realX y= $realY, robot=${_activeRobotId ?? 'None'} task=$taskId, TaskType: Disease.';

    try {
      await Supabase.instance.client.from('chats').insert({
        'task_id': taskId,
        'user_id': _currentUser!.id,
        'sender': 'user',
        'message': text,
        'session_id': _currentSessionId,
      });
    } catch (e) {
      debugPrint('DB(user msg): $e');
    }
    try {
      await Supabase.instance.client.from('task_history').insert({
        'task_id': taskId,
        'user_id': _currentUser!.id,
        'robot_id': _activeRobotId,
        'plant_location': '$_selectedRow,$_selectedCol',
        'execution_time': DateTime.now().toUtc().toIso8601String(),
        'status': 'incomplete',
        'is_scheduled': false,
      });
    } catch (e) {
      debugPrint('DB(task history): $e');
    }

    try {
      final resp = await Supabase.instance.client.functions
          .invoke('anubix_chat', body: {
        'prompt': text,
        'task_id': taskId,
        'systemContext': sysCtx,
      });
      if (resp.status == 200) {
        final agentText = resp.data['text'] ?? 'No response text found.';
        try {
          await Supabase.instance.client.from('chats').insert({
            'task_id': taskId,
            'user_id': _currentUser!.id,
            'sender': 'anubix',
            'message': agentText,
            'session_id': _currentSessionId,
          });
        } catch (e) {
          debugPrint('DB(agent msg): $e');
        }
        setState(() => _chatMessages.add({'role': 'agent', 'text': agentText}));
      } else {
        setState(() => _chatMessages
            .add({'role': 'agent', 'text': 'Connection Error: ${resp.status}'}));
      }
    } catch (e) {
      setState(() =>
          _chatMessages.add({'role': 'agent', 'text': 'Cloud Error: $e'}));
    } finally {
      setState(() {
        _isWaitingForAgent = false;
        _selectedPlantZone = null;
        _selectedRow = null;
        _selectedCol = null;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _driveRobotTo(int tRow, int tCol) async {
    if (_isInitialLoad) {
      setState(() {
        _currentRow = tRow;
        _currentCol = tCol;
        _robotLeft = _pathCenterX(tCol);
        _robotTop = _rowCenterY(tRow);
        _isInitialLoad = false;
      });
      return;
    }
    if (_currentRow == tRow && _currentCol == tCol) return;
    if (_isDriving) return;
    _isDriving = true;

    if (_currentRow == tRow) {
      setState(() {
        _animationSpeed = 1500;
        _robotLeft = _pathCenterX(tCol);
        _currentCol = tCol;
      });
      await Future.delayed(const Duration(milliseconds: 1500));
      _isDriving = false;
      return;
    }

    final aisleX = _pathCenterX(tCol);
    setState(() {
      _animationSpeed = 1000;
      _robotLeft = aisleX;
    });
    await Future.delayed(const Duration(milliseconds: 1000));

    setState(() {
      _animationSpeed = 1200;
      _robotTop = _rowCenterY(tRow);
    });
    await Future.delayed(const Duration(milliseconds: 1200));

    setState(() {
      _animationSpeed = 600;
      _robotLeft = _pathCenterX(tCol);
      _currentRow = tRow;
      _currentCol = tCol;
    });
    await Future.delayed(const Duration(milliseconds: 600));

    _isDriving = false;
  }

  void _showPlantDetails(int r, int c, Color statusColor, String statusText) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: statusColor.withAlpha(120), width: 1.5),
        ),
        title: Row(children: [
          Icon(Icons.eco_rounded, color: statusColor, size: 20),
          const SizedBox(width: 10),
          Text('Crop Report — Zone $r,$c',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: FutureBuilder<Map<String, dynamic>?>(
                future: Supabase.instance.client
                    .from('readings')
                    .select('photo_1_url')
                    .eq('plant_location', '$r,$c')
                    .order('recorded_at', ascending: false)
                    .limit(1)
                    .maybeSingle(),
                builder: (context, snap) {
                  Widget img;
                  if (snap.connectionState == ConnectionState.waiting) {
                    img = const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.orange, strokeWidth: 2));
                  } else if (snap.data?['photo_1_url'] == null) {
                    img = const Center(
                        child: Text('No Photo Available',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 12)));
                  } else {
                    img = ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(snap.data!['photo_1_url'],
                          fit: BoxFit.cover,
                          errorBuilder: (a, b, c2) => const Icon(
                              Icons.broken_image,
                              color: AppColors.textMuted)),
                    );
                  }
                  return Container(
                    height: 130,
                    width: 130,
                    decoration: BoxDecoration(
                        color: AppColors.bgPrimary,
                        borderRadius: BorderRadius.circular(8)),
                    child: img,
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text('Status: $statusText',
                  style: TextStyle(
                      color: statusColor, fontWeight: FontWeight.bold)),
            ]),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close',
                style: TextStyle(color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  Widget _buildTomatoPlant(double w, double h, bool selected) {
    final fruitSz = math.max(5.0, math.min(14.0, w * 0.085));
    final leafSz = math.max(10.0, math.min(24.0, w * 0.16));
    final stemW = math.max(1.8, w * 0.014);
    final stemH = math.max(5.0, h * 0.20);
    final stakeH = math.max(8.0, h * 0.55);
    final stakeW = math.max(1.2, w * 0.009);

    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: 0,
            child: Container(
              width: w * 0.35,
              height: h * 0.05,
              decoration: BoxDecoration(
                color: const Color(0xFF2A1A08).withAlpha(50),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),
          Positioned(
            bottom: h * 0.02,
            child: Container(
              width: stakeW,
              height: stakeH,
              decoration: BoxDecoration(
                color: const Color(0xFF6D4C41).withAlpha(150),
                borderRadius: BorderRadius.circular(stakeW),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _fruit(fruitSz * 0.65),
                  SizedBox(width: fruitSz * 0.2),
                  _fruit(fruitSz),
                  SizedBox(width: fruitSz * 0.2),
                  _fruit(fruitSz * 0.75),
                ],
              ),
              SizedBox(height: stemH * 0.12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.rotate(
                      angle: 0.35,
                      child: Icon(Icons.eco,
                          color: const Color(0xFF2D6B12),
                          size: leafSz * 0.65)),
                  SizedBox(width: fruitSz * 0.08),
                  Transform.rotate(
                      angle: -0.35,
                      child: Icon(Icons.eco,
                          color: const Color(0xFF3A7D24),
                          size: leafSz * 0.65)),
                ],
              ),
              Container(
                width: stemW + 1,
                height: stemH,
                decoration: BoxDecoration(
                  color: const Color(0xFF2B5F14),
                  borderRadius: BorderRadius.circular(stemW),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.rotate(
                      angle: 0.5,
                      child: Icon(Icons.eco,
                          color: const Color(0xFF2E7D32), size: leafSz)),
                  SizedBox(width: fruitSz * 0.04),
                  Transform.rotate(
                      angle: -0.5,
                      child: Icon(Icons.eco,
                          color: const Color(0xFF1B5E20),
                          size: leafSz * 0.85)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fruit(double sz) => Container(
        width: sz,
        height: sz,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [Color(0xFFE53935), Color(0xFFC62828)],
            center: Alignment(-0.3, -0.35),
            radius: 0.65,
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha(60),
                blurRadius: 2,
                offset: const Offset(0, 1)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Center(
          child: Text('Authentication required.',
              style: TextStyle(color: AppColors.textPrimary)));
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _profileStream,
      builder: (context, profileSnap) {
        if (!profileSnap.hasData || profileSnap.data!.isEmpty) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.orange));
        }

        final profile = profileSnap.data!.first;
        final int rows = profile['grid_rows'] ?? 4;
        final int cols = profile['grid_columns'] ?? 6;

        _cachedRows = rows;
        _cachedDistRows =
            (profile['distance_between_rows'] as num?)?.toDouble() ?? 10.0;
        _cachedDistCols =
            (profile['distance_between_columns'] as num?)?.toDouble() ??
                _cachedDistRows;

        return Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            margin: const EdgeInsets.only(top: 12, left: 20, right: 20),
            decoration: BoxDecoration(
              color: AppColors.bgSecondary,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('FARM MONITOR',
                    style: TextStyle(
                        color: AppColors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 1.5)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.bgPrimary,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.grid_view_rounded,
                        color: AppColors.textMuted, size: 14),
                    const SizedBox(width: 8),
                    Text('$rows rows  x  $cols columns',
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5)),
                  ]),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: LayoutBuilder(builder: (context, constraints) {
                _computeLayout(
                    rows, cols, constraints.maxWidth, constraints.maxHeight);

                final fieldW = cols * _cellW + (cols + 1) * _pathW;
                final fieldH = (rows + 1) * _cellH + (rows + 2) * _pathW;

                return Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.fieldDark,
                        AppColors.fieldMid,
                        AppColors.fieldLight,
                        AppColors.fieldMid,
                        AppColors.fieldDark,
                      ],
                      stops: [0.0, 0.2, 0.5, 0.8, 1.0],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: AppColors.border.withAlpha(100)),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: fieldW,
                      height: fieldH,
                      child: Stack(clipBehavior: Clip.hardEdge, children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _FieldOverlayPainter(
                              rows: rows,
                              cols: cols,
                              cellW: _cellW,
                              cellH: _cellH,
                              gapW: _pathW,
                              selRow: _selectedRow,
                              selCol: _selectedCol,
                            ),
                          ),
                        ),
                        for (int gi = 0; gi < rows * cols; gi++)
                          _plantOverlay(gi, rows, cols),
                        _homeBaseLabel(rows),
                        AnimatedPositioned(
                          duration: Duration(milliseconds: _animationSpeed),
                          curve: Curves.easeInOut,
                          left: _robotLeft ?? _pathCenterX(1),
                          top: _robotTop ?? _rowCenterY(0),
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()..scale(-1.0, 1.0),
                            child: SizedBox(
                              width: _robotSz,
                              height: _robotSz,
                              child:
                                  Image.asset(robotAsset, fit: BoxFit.contain),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                );
              }),
            ),
          ),
          if (_selectedPlantZone != null)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.orange.withAlpha(25),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: AppColors.orange.withAlpha(80)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.my_location,
                        color: AppColors.orange, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Target: Row $_selectedRow, Col $_selectedCol',
                      style: const TextStyle(
                          color: AppColors.orange,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() {
                        _selectedPlantZone = null;
                        _selectedRow = null;
                        _selectedCol = null;
                      }),
                      child: const Icon(Icons.close,
                          color: AppColors.orange, size: 14),
                    ),
                  ]),
                ),
              ),
            ),
          if (_chatMessages.isNotEmpty)
            Flexible(
              flex: 0,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.bgSecondary,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ListView.builder(
                    controller: _scrollController,
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(12),
                    itemCount:
                        _chatMessages.length + (_isWaitingForAgent ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _chatMessages.length) {
                        return const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.orange),
                            ),
                          ),
                        );
                      }
                      final msg = _chatMessages[index];
                      final isUser = msg['role'] == 'user';
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.5),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isUser
                                ? AppColors.accent.withAlpha(35)
                                : AppColors.orange.withAlpha(25),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(msg['text']!,
                              style: TextStyle(
                                  color: isUser
                                      ? AppColors.accent
                                      : AppColors.orangeLight,
                                  fontSize: 13)),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          Container(
            height: 50,
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _selectedPlantZone == null
                  ? AppColors.bgPrimary
                  : AppColors.bgSecondary,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                  color: _selectedPlantZone == null
                      ? AppColors.border
                      : AppColors.borderLight),
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  enabled: _selectedPlantZone != null,
                  style: TextStyle(
                      color: _selectedPlantZone == null
                          ? AppColors.textMuted
                          : AppColors.textPrimary),
                  onSubmitted: (_) => _sendMessageToAgent(),
                  decoration: InputDecoration(
                    hintText: _selectedPlantZone == null
                        ? 'Select a crop zone on the field to begin...'
                        : 'Enter command for Row $_selectedRow, Col $_selectedCol...',
                    hintStyle: TextStyle(
                        color: _selectedPlantZone == null
                            ? AppColors.textMuted
                            : AppColors.textSecondary),
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.send_rounded,
                    color: _selectedPlantZone == null
                        ? AppColors.textMuted
                        : AppColors.orange),
                onPressed:
                    _selectedPlantZone == null ? null : _sendMessageToAgent,
              ),
            ]),
          ),
        ]);
      },
    );
  }

  Widget _plantOverlay(int gi, int rows, int cols) {
    final visualRow = gi ~/ cols;
    final c = (gi % cols) + 1;
    final r = rows - visualRow;

    final cellLeft = c * _pathW + (c - 1) * _cellW;
    final cellTop = visualRow * (_cellH + _pathW) + _pathW;

    final dotSz = math.max(5.0, math.min(9.0, _cellW * 0.06));
    final labelSz = math.max(5.0, math.min(9.0, _cellW * 0.052));

    return Positioned(
      left: cellLeft,
      top: cellTop,
      width: _cellW,
      height: _cellH,
      child: FutureBuilder<Map<String, dynamic>?>(
        future: Supabase.instance.client
            .from('readings')
            .select('disease_detected')
            .eq('plant_location', '$r,$c')
            .order('recorded_at', ascending: false)
            .limit(1)
            .maybeSingle(),
        builder: (context, snap) {
          Color statusColor = AppColors.unknown;
          String statusText = 'Unknown';

          if (snap.connectionState == ConnectionState.waiting) {
            statusColor = AppColors.textMuted;
            statusText = 'Checking...';
          } else if (snap.hasData && snap.data != null) {
            final diseased = snap.data!['disease_detected'];
            if (diseased == true) {
              statusColor = AppColors.diseased;
              statusText = 'Diseased';
            } else if (diseased == false) {
              statusColor = AppColors.healthy;
              statusText = 'Healthy';
            }
          }

          return MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) {
              _hoverTimer = Timer(const Duration(milliseconds: 1800),
                  () => _showPlantDetails(r, c, statusColor, statusText));
            },
            onExit: (_) => _hoverTimer?.cancel(),
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedPlantZone = '$r,$c';
                _selectedRow = r;
                _selectedCol = c;
              }),
              child: Container(
                color: Colors.transparent,
                clipBehavior: Clip.hardEdge,
                decoration: const BoxDecoration(),
                child: Stack(children: [
                  Center(
                      child: _buildTomatoPlant(
                          _cellW, _cellH, r == _selectedRow && c == _selectedCol)),
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      width: dotSz,
                      height: dotSz,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: statusColor.withAlpha(140), blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 3,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(100),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text('$r,$c',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: labelSz,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _homeBaseLabel(int rows) {
    final homeRowTop = rows * (_cellH + _pathW) + _pathW;
    final padLeft = _pathW;
    final iconSz = math.max(10.0, math.min(20.0, _cellH * 0.32));
    final fontSz = math.max(5.5, math.min(10.0, _cellW * 0.057));

    return Positioned(
      left: padLeft,
      top: homeRowTop,
      width: _cellW,
      height: _cellH,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.precision_manufacturing_rounded,
            color: AppColors.orange, size: iconSz),
        const SizedBox(height: 2),
        Text('HOME  0,1',
            style: TextStyle(
                color: AppColors.orange,
                fontSize: fontSz,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8)),
      ]),
    );
  }
}
