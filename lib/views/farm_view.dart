import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class FarmView extends StatefulWidget {
  const FarmView({super.key});

  @override
  State<FarmView> createState() => _FarmViewState();
}

class _FarmViewState extends State<FarmView> {
  final _currentUser = Supabase.instance.client.auth.currentUser;

  // Initialize the UUID generator
  final _uuid = const Uuid();
  
  // --- YOUR LOCAL ASSETS ---
  final String plantAsset = 'assets/images/plant.png'; 
  final String robotAsset = 'assets/images/robot.png'; 

  // --- 3D FARM COLORS ---
  final Color deepDirtPath = const Color(0xFF2C1E16); 
  final Color raisedDirtBed = const Color(0xFF4A3525); 
  final Color bedBorder = const Color(0xFF382619); 

  late Stream<List<Map<String, dynamic>>> _profileStream;
  StreamSubscription<List<Map<String, dynamic>>>? _robotSubscription;
  final TextEditingController _chatController = TextEditingController();

  // --- CHAT AGENT STATE ---
  final List<Map<String, String>> _chatMessages = [];
  bool _isWaitingForAgent = false;
  final ScrollController _scrollController = ScrollController();

  // --- MAP DIMENSIONS ---
  static const double cellWidth = 180.0;  
  static const double cellHeight = 90.0;  
  static const double pathWidth = 60.0;   
  static const double robotSize = 55.0;   

  // --- SPATIAL CONTEXT & ROUTING ---
  double? _robotLeft;
  double? _robotTop;
  int _currentRow = 1;
  int _currentCol = 1;
  bool _isInitialLoad = true;
  bool _isDriving = false;
  int _animationSpeed = 1200; 
  String? _activeRobotId;
  String? _selectedPlantZone; 
  int? _selectedRow;          
  int? _selectedCol;          
  Timer? _hoverTimer; 
  
  // --- SESSION ID ---
  late String _currentSessionId;

  // --- THE F12 CONSOLE LISTENER VARIABLE ---
  RealtimeChannel? _consoleSubscription;

  // --- PHYSICAL DISTANCE CACHE (For Logical <-> Physical Translation) ---
  double _cachedDistRows = 10.0;
  double _cachedDistCols = 10.0;

  double _getCenterPathX(int col) => pathWidth + ((col - 1) * (cellWidth + pathWidth)) + (cellWidth / 2) - (robotSize / 2);
  double _getBottomPathY(int row) => pathWidth + ((row - 1) * (cellHeight + pathWidth)) + cellHeight + (pathWidth / 2) - (robotSize / 2);

  @override
  void initState() {
    super.initState();
    
    final now = DateTime.now();
    _currentSessionId = 'Dashboard - ${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')} ${now.hour}:${now.minute.toString().padLeft(2,'0')}';

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
        final activeRobot = data.first;
        _activeRobotId = activeRobot['robot_id'];
        
        if (activeRobot['current_location'] != null) {
          final parts = activeRobot['current_location'].toString().split(',');
          if (parts.length == 2) {
            // TRANSLATION: DB (Physical CM) -> UI (Logical Grid)
            double physX = double.tryParse(parts[0]) ?? _cachedDistRows;
            double physY = double.tryParse(parts[1]) ?? _cachedDistCols;

            // Divide by distance to get grid cell, round to nearest whole cell
            int targetRow = (physX / (_cachedDistRows > 0 ? _cachedDistRows : 1)).round();
            int targetCol = (physY / (_cachedDistCols > 0 ? _cachedDistCols : 1)).round();

            // Failsafe to keep robot on the grid
            if (targetRow < 1) targetRow = 1;
            if (targetCol < 1) targetCol = 1;

            _driveRobotTo(targetRow, targetCol);
          }
        }
      }
    });
  }

  void _listenForAutomatedBackendTasks() {
    _consoleSubscription = Supabase.instance.client
        .channel('farm_view_listener_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chats',
          callback: (payload) {
            final sender = payload.newRecord['sender'];
            final message = payload.newRecord['message'];

            debugPrint("\n==============================================");
            debugPrint("🟢 [FARM VIEW] BACKEND TRIGGER DETECTED!");
            debugPrint("Sender: ${sender.toString().toUpperCase()}");
            debugPrint("Message: $message");
            debugPrint("==============================================\n");
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

  
  // ==========================================
  // UPDATED: PHYSICAL DISTANCE CHAT AGENT
  // ==========================================
  Future<void> _sendMessageToAgent() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _currentUser == null) return;

    if (_selectedPlantZone == null || _selectedRow == null || _selectedCol == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Select a plant zone before sending a command.'), backgroundColor: Colors.orange));
      return;
    }

    setState(() {
      _chatMessages.add({'role': 'user', 'text': text});
      _isWaitingForAgent = true;
    });
    _chatController.clear();
    _scrollToBottom();

    // --- CALCULATE MATH USING FAST CACHED DISTANCES ---
    double realX = _selectedRow! * _cachedDistRows;
    double realY = _selectedCol! * _cachedDistCols;

    // ==========================================
    // --- ADDED: GENERATE IDs LOCALLY INSTANTLY ---
    // ==========================================
    final String generatedTaskId = const Uuid().v4(); // Unique ID for the task history

    // ==========================================
    // --- MODIFIED: SPLIT THE PROMPT FOR CLEAN UI ---
    // ==========================================
    // We isolate the hidden data so the Mock Agent doesn't echo it on the screen!
    String hiddenSystemContext = "The exact physical location target is X: ${realX}cm, Y: ${realY}cm. TaskID: $generatedTaskId. RobotID: ${_activeRobotId ?? 'None'}. TaskType: disease. Do not use previous chat history for this command.";

    debugPrint('\n========== ANUBIX COMM START ==========');
    debugPrint('[LOCAL] RAW USER TEXT: $text');
    debugPrint('[LOCAL] Generated Task ID: $generatedTaskId'); 
    debugPrint('[LOCAL] HIDDEN SYSTEM CONTEXT:\n$hiddenSystemContext');

    // 1. Save User Message
    try {
      await Supabase.instance.client.from('chats').insert({
        'task_id': generatedTaskId, // --- ADDED: Link message to the task
        'user_id': _currentUser!.id,
        'sender': 'user',
        'message': text, // Just the clean text
        'session_id': _currentSessionId,
      });
    } catch (e) {
      debugPrint('Database Error (User Msg): $e');
    }

    // ==========================================
    // --- ADDED: CREATE TASK HISTORY RECORD ---
    // ==========================================
    try {
      await Supabase.instance.client.from('task_history').insert({
        'task_id': generatedTaskId,
        'user_id': _currentUser!.id,
        'robot_id': _activeRobotId,
        'plant_location': '$realX,$realY',
        'task_type': 'diagnosis', // Hardcoded as you wanted!
        'execution_time': DateTime.now().toUtc().toIso8601String(),
        'status': 'incomplete',
        'is_scheduled': false
      });
    } catch (e) {
      debugPrint('Database Error (Task History): $e');
    }

    // 2. Invoke Cloud Edge Function
    try {
      // --- MODIFIED: Using the Split Payload so the UI stays clean!
      final response = await Supabase.instance.client.functions.invoke(
        'anubix_chat',
        body: {
          "prompt": text,                       // <--- ONLY THE CLEAN TEXT
          "history": "",                        // <--- No history for a new farm command
          "systemContext": hiddenSystemContext, // <--- Hidden coordinates, IDs, and diagnosis tag
          "agentName": "ANUBIX"
        },
      );

      if (response.status == 200) {
        final agentText = response.data['text'] ?? 'No response text found.';

        // 3. Save Agent Message
        try {
          await Supabase.instance.client.from('chats').insert({
            'task_id': generatedTaskId,   // --- ADDED: Link AI's reply to the same task
            'user_id': _currentUser!.id,
            'sender': 'anubix', 
            'message': agentText, // Clean response from the AI
            'session_id': _currentSessionId,
          });
        } catch (e) {
          debugPrint('Database Error (Agent Msg): $e');
        }

        setState(() => _chatMessages.add({'role': 'agent', 'text': agentText}));
      } else {
        setState(() => _chatMessages.add({'role': 'agent', 'text': 'Connection Error: ${response.status}'}));
      }
    } catch (e) {
      setState(() => _chatMessages.add({'role': 'agent', 'text': 'Cloud Error: $e'}));
    } finally {
      debugPrint('========== ANUBIX COMM END ==========\n');
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

  Future<void> _driveRobotTo(int targetRow, int targetCol) async {
    if (_isInitialLoad) {
      setState(() {
        _currentRow = targetRow;
        _currentCol = targetCol;
        _robotLeft = _getCenterPathX(targetCol);
        _robotTop = _getBottomPathY(targetRow);
        _isInitialLoad = false;
      });
      return;
    }

    if (_currentRow == targetRow && _currentCol == targetCol) return;
    if (_isDriving) return; 
    _isDriving = true;

    if (_currentRow == targetRow) {
      setState(() {
        _animationSpeed = 1500;
        _robotLeft = _getCenterPathX(targetCol);
        _currentCol = targetCol;
      });
      await Future.delayed(const Duration(milliseconds: 1500));
      _isDriving = false;
      return;
    }

    double targetAisleX;
    if (_currentCol < targetCol) {
      targetAisleX = ((targetCol - 1) * (cellWidth + pathWidth)) + (pathWidth / 2) - (robotSize / 2);
    } else {
      targetAisleX = (targetCol * (cellWidth + pathWidth)) + (pathWidth / 2) - (robotSize / 2);
    }

    setState(() {
      _animationSpeed = 1000;
      _robotLeft = targetAisleX;
    });
    await Future.delayed(const Duration(milliseconds: 1000));

    setState(() {
      _animationSpeed = 1200;
      _robotTop = _getBottomPathY(targetRow);
    });
    await Future.delayed(const Duration(milliseconds: 1200));

    setState(() {
      _animationSpeed = 600; 
      _robotLeft = _getCenterPathX(targetCol);
      _currentRow = targetRow;
      _currentCol = targetCol;
    });
    await Future.delayed(const Duration(milliseconds: 600));

    _isDriving = false;
  }

  Future<void> _updateGridSize(int rows, int cols) async {
    if (_currentUser == null) return;
    try {
      await Supabase.instance.client.from('profiles').update({
        'grid_rows': rows,
        'grid_columns': cols,
      }).eq('id', _currentUser!.id);
    } catch (e) {
      debugPrint('Grid Update Error: $e');
    }
  }

  Future<void> _dispatchRobot(String robotId, int r, int c) async {
    try {
      // TRANSLATION: UI (Logical Grid) -> DB (Physical CM)
      double realX = r * _cachedDistRows;
      double realY = c * _cachedDistCols;

      await Supabase.instance.client.from('robots').update({'current_location': '$realX,$realY'}).eq('robot_id', robotId);
      
      if (mounted) {
        Navigator.pop(context); 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🚀 Anubix routing to Physical Coordinates ($realX, $realY)...'), backgroundColor: Colors.greenAccent, behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Transmission Failed: $e'), backgroundColor: Colors.redAccent));
    }
  }

  void _showPlantDetails(int r, int c, Color statusColor, String statusText) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: statusColor, width: 2)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: statusColor),
              const SizedBox(width: 10),
              Text('Crop Report ($r,$c)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Container(height: 80, width: 80, decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)), child: const Center(child: Text('Disease\nPhoto', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12)))),
                  Container(height: 80, width: 80, decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)), child: const Center(child: Text('Water\nPhoto', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12)))),
                ],
              ),
              const SizedBox(height: 20),
              Text('Status: $statusText', style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
              const Text('Harvest: In Progress', style: TextStyle(color: Colors.white70)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: Colors.white54))),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: statusColor.withOpacity(0.2), foregroundColor: statusColor, side: BorderSide(color: statusColor)),
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Dispatch Anubix'),
              onPressed: () {
                if (_activeRobotId != null) {
                  _dispatchRobot(_activeRobotId!, r, c);
                }
              },
            )
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) return const Center(child: Text("Authentication required.", style: TextStyle(color: Colors.white)));

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _profileStream,
      builder: (context, profileSnapshot) {
        if (!profileSnapshot.hasData || profileSnapshot.data!.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: Colors.green));
        }

        final profile = profileSnapshot.data!.first;
        final int rows = profile['grid_rows'] ?? 4;
        final int cols = profile['grid_columns'] ?? 6;

        // Quietly update our cached physical distances for translation mapping
        _cachedDistRows = (profile['distance_between_rows'] as num?)?.toDouble() ?? 10.0;
        _cachedDistCols = (profile['distance_between_columns'] as num?)?.toDouble() ?? _cachedDistRows;

        final double totalFieldWidth = (cols * cellWidth) + ((cols + 1) * pathWidth);
        final double totalFieldHeight = (rows * cellHeight) + ((rows + 1) * pathWidth);

        return Column(
          children: [
            // --- TOP HEADER ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.only(top: 12, left: 20, right: 20),
              decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('CONTROL PANEL', style: TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.2)),
                  Row(
                    children: [
                      const Text('Rows: ', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      DropdownButton<int>(
                        value: rows, dropdownColor: Colors.black87, style: const TextStyle(color: Colors.white, fontSize: 14),
                        items: List.generate(10, (i) => i + 1).map((e) => DropdownMenuItem(value: e, child: Text(e.toString()))).toList(),
                        onChanged: (val) => _updateGridSize(val!, cols),
                      ),
                      const SizedBox(width: 12),
                      const Text('Cols: ', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      DropdownButton<int>(
                        value: cols, dropdownColor: Colors.black87, style: const TextStyle(color: Colors.white, fontSize: 14),
                        items: List.generate(10, (i) => i + 1).map((e) => DropdownMenuItem(value: e, child: Text(e.toString()))).toList(),
                        onChanged: (val) => _updateGridSize(rows, val!),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // --- THE DIGITAL TWIN FIELD ---
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: deepDirtPath, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black87, width: 4)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: totalFieldWidth,
                        height: totalFieldHeight,
                        child: Stack(
                          children: [
                            GridView.builder(
                              padding: const EdgeInsets.all(pathWidth),
                              physics: const NeverScrollableScrollPhysics(), 
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols, crossAxisSpacing: pathWidth, mainAxisSpacing: pathWidth, childAspectRatio: cellWidth / cellHeight,
                              ),
                              itemCount: rows * cols,
                              itemBuilder: (context, index) {
                                int r = (index ~/ cols) + 1;
                                int c = (index % cols) + 1;
                                
                                Color statusColor = Colors.greenAccent;
                                String statusText = "Normal";
                                if (index % 7 == 0) { statusColor = Colors.redAccent; statusText = "Disease Detected"; } 
                                else if (index % 5 == 0) { statusColor = Colors.lightBlueAccent; statusText = "High Water Stress"; }

                                return MouseRegion(
                                  onEnter: (_) {
                                    _hoverTimer = Timer(const Duration(milliseconds: 1000), () {
                                      _showPlantDetails(r, c, statusColor, statusText);
                                    });
                                  },
                                  onExit: (_) {
                                    _hoverTimer?.cancel();
                                  },
                                  child: GestureDetector(
                                    onTap: () {
                                      // SAVING THE REAL GRID COORDINATES TO MEMORY
                                      setState(() {
                                        _selectedPlantZone = 'Zone ($r, $c)';
                                        _selectedRow = r;
                                        _selectedCol = c;
                                      });
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(color: raisedDirtBed, borderRadius: BorderRadius.circular(12), border: Border.all(color: bedBorder)),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Image.asset(plantAsset, fit: BoxFit.contain),
                                          Positioned(top: 6, left: 6, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle))),
                                          Positioned(
                                            bottom: 6, right: 6,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                              decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(4)),
                                              child: Text('($r,$c)', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            AnimatedPositioned(
                              duration: Duration(milliseconds: _animationSpeed), 
                              curve: Curves.easeInOut, 
                              left: _robotLeft ?? _getCenterPathX(1),
                              top: _robotTop ?? _getBottomPathY(1),
                              child: SizedBox(width: robotSize, height: robotSize, child: Image.asset(robotAsset, fit: BoxFit.contain)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // --- ACTIVE TARGET CHIP ---
            if (_selectedPlantZone != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.greenAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.greenAccent.withOpacity(0.3))),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.my_location, color: Colors.greenAccent, size: 14),
                          const SizedBox(width: 6),
                          Text('Targeting: $_selectedPlantZone', style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedPlantZone = null;
                                _selectedRow = null;
                                _selectedCol = null;
                              });
                            }, 
                            child: const Icon(Icons.close, color: Colors.greenAccent, size: 14)
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // --- CHAT MESSAGES ---
            if (_chatMessages.isNotEmpty)
              Container(
                height: 120, margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
                child: ListView.builder(
                  controller: _scrollController, padding: const EdgeInsets.all(12),
                  itemCount: _chatMessages.length + (_isWaitingForAgent ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _chatMessages.length) return const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent));
                    final msg = _chatMessages[index];
                    bool isUser = msg['role'] == 'user';
                    return Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: isUser ? Colors.blue.withOpacity(0.2) : Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                        child: Text(msg['text']!, style: TextStyle(color: isUser ? Colors.lightBlueAccent : Colors.greenAccent)),
                      ),
                    );
                  },
                ),
              ),

            // --- CHAT INPUT BAR (LOCKED) ---
            Container(
              height: 50, margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _selectedPlantZone == null ? const Color(0xFF121212) : const Color(0xFF1E1E1E), 
                borderRadius: BorderRadius.circular(30), 
                border: Border.all(color: _selectedPlantZone == null ? Colors.white10 : Colors.white24)
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatController, 
                      enabled: _selectedPlantZone != null, // <-- LOCKED IF NO ZONE SELECTED
                      style: TextStyle(color: _selectedPlantZone == null ? Colors.white30 : Colors.white), 
                      onSubmitted: (_) => _sendMessageToAgent(), 
                      decoration: InputDecoration(
                        hintText: _selectedPlantZone == null ? 'Select a target zone on the map to unlock chat...' : 'Command Anubix for $_selectedPlantZone...', 
                        hintStyle: TextStyle(color: _selectedPlantZone == null ? Colors.white30 : Colors.white54),
                        border: InputBorder.none, 
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20)
                      )
                    )
                  ),
                  IconButton(
                    icon: Icon(Icons.send, color: _selectedPlantZone == null ? Colors.grey : Colors.lightBlueAccent), 
                    onPressed: _selectedPlantZone == null ? null : _sendMessageToAgent
                  ),
                ],
              ),
            ),
          ],
        );
      }
    );
  }
}