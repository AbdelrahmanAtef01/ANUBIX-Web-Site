import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OldChatsView extends StatefulWidget {
  const OldChatsView({super.key});

  @override
  State<OldChatsView> createState() => _OldChatsViewState();
}

class _OldChatsViewState extends State<OldChatsView> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<String> _sessions = [];
  String? _selectedSession;
  Stream<List<Map<String, dynamic>>>? _chatStream;
  bool _isWaitingForAgent = false;

  @override
  void initState() {
    super.initState();
    _fetchDynamicSessions();
  }

  Future<void> _fetchDynamicSessions() async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    try {
      final data = await Supabase.instance.client
          .from('chats')
          .select('session_id, created_at')
          .eq('user_id', currentUser.id)
          .order('created_at', ascending: false);

      final Set<String> uniqueSessions = {};
      for (var row in data) {
        final sid = row['session_id'] as String?;
        if (sid != null && sid.trim().isNotEmpty) {
          uniqueSessions.add(sid);
        }
      }

      if (mounted) {
        setState(() {
          _sessions = uniqueSessions.toList();
          if (_sessions.isNotEmpty && _selectedSession == null) {
            _selectedSession = _sessions.first;
            _setupChatStream();
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading sessions: $e');
    }
  }

  void _setupChatStream() {
    if (_selectedSession == null) return;
    _chatStream = Supabase.instance.client
        .from('chats')
        .stream(primaryKey: ['chat_id'])
        .eq('session_id', _selectedSession!)
        .order('created_at', ascending: true);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ==========================================
  // UPDATED: CONVERSATIONAL AGENT WITH MEMORY
  // ==========================================
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isWaitingForAgent || _selectedSession == null) return;

    setState(() {
      _isWaitingForAgent = true;
    });

    _messageController.clear();
    _scrollToBottom();

    final currentUser = Supabase.instance.client.auth.currentUser;

    // --- 1. FETCH CONTEXT & IDs ---
    String? historicalTaskId;
    String? historicalRobotId;

    // MODIFIED: Changed from a String to a List of Maps to match the backend expectation
    List<Map<String, String>> messagesArray = [];

    try {
      final historyData = await Supabase.instance.client
          .from('chats')
          .select('sender, message, task_id')
          .eq('session_id', _selectedSession!)
          .order(
            'created_at',
            ascending: false,
          ) // Latest first to get the 5 most recent
          .limit(5);

      if (historyData.isNotEmpty) {
        for (var msg in historyData) {
          if (msg['task_id'] != null) {
            historicalTaskId = msg['task_id'];
            break;
          }
        }

        if (historicalTaskId != null) {
          final taskData = await Supabase.instance.client
              .from('task_history')
              .select('robot_id')
              .eq('task_id', historicalTaskId)
              .maybeSingle();

          if (taskData != null) {
            historicalRobotId = taskData['robot_id'];
          }
        }

        // MODIFIED: Reverse the list so it's in ascending chronological order
        final recentMessages = historyData.reversed.toList();

        // Build the messages array for the Edge Function body
        messagesArray = recentMessages.map<Map<String, String>>((msg) {
          // Normalize sender names to 'user' or 'anubix'
          final role = (msg['sender'] == 'user') ? 'user' : 'anubix';
          return {"role": role, "content": msg['message'] ?? ''};
        }).toList();
      }
    } catch (e) {
      debugPrint('Warning: Could not fetch history for context: $e');
    }

    String hiddenSystemContext =
        "Task Id: ${historicalTaskId ?? 'None'}. Robot Id: ${historicalRobotId ?? 'None'}, TaskType: Disease.";

    debugPrint('\n========== ANUBIX COMM START ==========');
    debugPrint('[LOCAL] CLEAN TEXT (Saved to DB): $text');
    debugPrint('[LOCAL] HIDDEN CONTEXT (Sent to Cloud):\n$hiddenSystemContext');
    debugPrint('[LOCAL] HISTORY ARRAY:\n$messagesArray');

    // --- 2. SAVE USER MESSAGE ---
    try {
      await Supabase.instance.client.from('chats').insert({
        'sender': 'user',
        'message': text,
        'session_id': _selectedSession,
        'task_id': historicalTaskId,
        if (currentUser != null) 'user_id': currentUser.id,
      });
    } catch (e) {
      debugPrint('Failed to save your message: $e');
    }

    // --- 3. FETCH FROM SUPABASE EDGE FUNCTION ---
    String agentText = '';
    try {
      // MODIFIED: Passing the `messages` array exactly as you requested
      final response = await Supabase.instance.client.functions.invoke(
        'anubix_old_chats',
        body: {
          "prompt": text,
          "messages": messagesArray, // <--- Array of {role, content} maps
          "systemContext": hiddenSystemContext,
          'session_id': _selectedSession,
        },
      );

      if (response.status == 200) {
        agentText = response.data['text'] ?? 'Empty response received.';
      } else {
        agentText = 'Connection Error: ${response.status}';
      }
    } catch (e) {
      agentText = 'Cloud Proxy Error: $e';
    }

    // --- 4. SAVE AGENT MESSAGE ---
    try {
      await Supabase.instance.client.from('chats').insert({
        'sender': 'anubix',
        'message': agentText,
        'session_id': _selectedSession,
        'task_id': historicalTaskId,
        if (currentUser != null) 'user_id': currentUser.id,
      });
    } catch (dbError) {
      debugPrint('DATABASE REJECTED AGENT MESSAGE: $dbError');
    } finally {
      if (mounted) {
        setState(() {
          _isWaitingForAgent = false;
        });
        _scrollToBottom();
        debugPrint('========== ANUBIX COMM END ==========\n');
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 300), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- LEFT PANEL: Chat History List ---
          Container(
            width: 250,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text(
                    'Sessions',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Divider(color: Colors.white24, height: 1),
                Expanded(
                  child: _sessions.isEmpty
                      ? const Center(
                          child: Text(
                            "No chat history yet.",
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _sessions.length,
                          itemBuilder: (context, index) {
                            final sessionName = _sessions[index];
                            final isSelected = sessionName == _selectedSession;

                            return _buildChatListItem(
                              sessionName,
                              isSelected: isSelected,
                              onTap: () {
                                if (!isSelected) {
                                  setState(() {
                                    _selectedSession = sessionName;
                                    _setupChatStream();
                                  });
                                }
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 32),

          // --- RIGHT PANEL: The Active Chat Window ---
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: _selectedSession == null
                  ? const Center(
                      child: Text(
                        "Select a session to view.",
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Colors.white24),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.terminal,
                                color: Colors.lightBlueAccent,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Anubix Command Terminal: $_selectedSession',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.lightBlueAccent,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // --- REAL-TIME MESSAGES AREA ---
                        Expanded(
                          child: StreamBuilder<List<Map<String, dynamic>>>(
                            stream: _chatStream,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting)
                                return const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.lightBlueAccent,
                                  ),
                                );
                              if (snapshot.hasError)
                                return Center(
                                  child: Text(
                                    'Database Error: ${snapshot.error}',
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                );
                              final messages = snapshot.data ?? [];
                              if (messages.isEmpty && !_isWaitingForAgent)
                                return const Center(
                                  child: Text(
                                    'No messages yet. Send a command to Anubix.',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                );

                              WidgetsBinding.instance.addPostFrameCallback(
                                (_) => _scrollToBottom(),
                              );

                              return ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.all(24),
                                itemCount:
                                    messages.length +
                                    (_isWaitingForAgent ? 1 : 0),
                                itemBuilder: (context, index) {
                                  // SHOW THE INLINE LOADING SPINNER
                                  if (index == messages.length &&
                                      _isWaitingForAgent) {
                                    return const Align(
                                      alignment: Alignment.centerLeft,
                                      child: Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: SizedBox(
                                          height: 15,
                                          width: 15,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.greenAccent,
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  final msg = messages[index];
                                  final isUser = msg['sender'] == 'user';
                                  final text = msg['message'] ?? '';
                                  return _buildMessageBubble(
                                    text,
                                    isUser: isUser,
                                  );
                                },
                              );
                            },
                          ),
                        ),

                        // --- TEXT INPUT AREA ---
                        Container(
                          height: 50,
                          margin: const EdgeInsets.only(
                            left: 20,
                            right: 20,
                            bottom: 20,
                            top: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _messageController,
                                  style: const TextStyle(color: Colors.white),
                                  onSubmitted: (_) => _sendMessage(),
                                  decoration: const InputDecoration(
                                    hintText: 'Talk to Anubix Agent...',
                                    hintStyle: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 14,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 14,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.mic,
                                  color: Colors.lightBlueAccent,
                                  size: 20,
                                ),
                                onPressed: () {},
                              ),
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                decoration: const BoxDecoration(
                                  color: Colors.lightBlueAccent,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.send,
                                    color: Colors.black,
                                    size: 18,
                                  ),
                                  onPressed: _sendMessage,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatListItem(
    String title, {
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.lightBlueAccent.withOpacity(0.1)
            : Colors.transparent,
        border: Border(
          left: BorderSide(
            color: isSelected ? Colors.lightBlueAccent : Colors.transparent,
            width: 4,
          ),
        ),
      ),
      child: ListTile(
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.lightBlueAccent : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildMessageBubble(String text, {required bool isUser}) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? Colors.lightBlueAccent.withOpacity(0.2)
              : Colors.greenAccent.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUser
                ? Colors.lightBlueAccent.withOpacity(0.5)
                : Colors.greenAccent.withOpacity(0.5),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isUser ? Colors.lightBlueAccent : Colors.greenAccent,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
