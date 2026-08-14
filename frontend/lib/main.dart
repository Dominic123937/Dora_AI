import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:js' as js;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';




void main() {
  runApp(const GeminiWebApp());
}

class GeminiWebApp extends StatelessWidget {
  const GeminiWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dora AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0C10),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF8B5CF6),
          surface: Color(0xFF16181D),
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().textTheme,
        ).apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B0C10),
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: Colors.white),
        ),
        useMaterial3: true,
      ),
      home: const GeminiMainScreen(),
    );
  }
}



class ScrollRevealWidget extends StatefulWidget {
  final Widget child;
  final int delayMs;

  const ScrollRevealWidget({super.key, required this.child, this.delayMs = 0});

  @override
  State<ScrollRevealWidget> createState() => _ScrollRevealWidgetState();
}

class _ScrollRevealWidgetState extends State<ScrollRevealWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _slide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}

class CodeBlockBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  CodeBlockBuilder(this.context);

  @override
  Widget? visitElementAfter(dynamic element, TextStyle? preferredStyle) {
    String codeContent = element.textContent;
    String language = 'code';

    if (element.attributes != null && element.attributes['class'] != null) {
      final match = RegExp(r'language-(\w+)').firstMatch(element.attributes['class']!);
      if (match != null) {
        language = match.group(1) ?? 'code';
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1117),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2D3A), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar with Language Tag + 1-Click Copy Code Button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF161822),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFF2A2D3A), width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.code_rounded, color: Color(0xFF6366F1), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      language.toUpperCase(),
                      style: GoogleFonts.inter(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: codeContent));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Row(
                          children: [
                            Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 18),
                            SizedBox(width: 8),
                            Text('Code copied to clipboard!'),
                          ],
                        ),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF222533),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.copy_rounded, color: Color(0xFF6366F1), size: 12),
                        const SizedBox(width: 4),
                        Text(
                          'Copy Code',
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Code Content Body
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              codeContent,
              style: GoogleFonts.jetBrainsMono(
                color: const Color(0xFFF1F5F9),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GeminiMainScreen extends StatefulWidget {


  const GeminiMainScreen({super.key});

  @override
  State<GeminiMainScreen> createState() => _GeminiMainScreenState();
}


  

class _GeminiMainScreenState extends State<GeminiMainScreen> with TickerProviderStateMixin {

String get _apiBaseUrl => kIsWeb && !Uri.base.host.contains('localhost') && !Uri.base.host.contains('127.0.0.1')
    ? 'https://dora-ai-backend.onrender.com'
    : 'http://127.0.0.1:8000';

String get _wsBaseUrl => kIsWeb && !Uri.base.host.contains('localhost') && !Uri.base.host.contains('127.0.0.1')
    ? 'wss://dora-ai-backend.onrender.com'
    : 'ws://127.0.0.1:8000';

  Offset _cursorPosition = const Offset(600, 300);
  late AnimationController _bgAnimationController;
  late Animation<double> _bgAnimation;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  final List<String> _recentChats = [];


  String _selectedCategory = 'All';
  String _selectedModel = 'flash'; // 'flash' (Dora Flash) or 'pro' (Dora Pro)
  String? _activeThreadTitle;
  bool _isTyping = false;

  bool _isListening = false;
  bool _isDeepResearch = false;
  bool _showCanvas = false;
  String _activeCanvasTitle = 'Code Sandbox';
  String _activeCanvasLanguage = 'python';
  String _activeCanvasCode = '''# Dora AI Code Sandbox

import requests

def run_pipeline():
    print("Executing script in Dora Canvas...")
    return {"status": "active", "latency": "24ms", "tokens_per_sec": 850}

if __name__ == "__main__":
    run_pipeline()
''';

  String _activeToolStatus = '';
  String _currentWords = '';
  List<Map<String, String>> _currentSources = [];
  String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  String? _attachedFileName;
  String? _attachedFileContent;
  bool _isUploadingFile = false;
  bool _isSpeaking = false;

  String get _activeUserEmail => _googleUser?.email ?? _googleUserMap?['email'] ?? 'guest';

  void _speakText(String text) {
    setState(() => _isSpeaking = !_isSpeaking);
  }

  void _openCanvas(String title, String code, String lang) {
    setState(() {
      _showCanvas = true;
      _activeCanvasTitle = title;
      _activeCanvasCode = code;
      _activeCanvasLanguage = lang;
    });
  }

  WebSocketChannel? _wsChannel;
  final stt.SpeechToText _speech = stt.SpeechToText();
  late AnimationController _micAnimationController;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: '654296858110-fpop5lrjmod70bds48bavbhon54o55i5.apps.googleusercontent.com',
    scopes: ['email', 'profile'],
  );

  GoogleSignInAccount? _googleUser;
  Map<String, String>? _googleUserMap;
  Map<String, List<Map<String, dynamic>>> _cloudChatThreads = {};

  void _loadLocalChatsForUser(String email) {
    if (kIsWeb) {
      try {
        final localDataStr = js.context.callMethod('loadLocalChats', [email]);
        if (localDataStr != null && localDataStr.toString().isNotEmpty) {
          final data = jsonDecode(localDataStr.toString());
          final List localRecents = data['recentChats'] as List? ?? [];
          final Map localThreads = data['threads'] as Map? ?? {};
          setState(() {
            _recentChats.clear();
            _recentChats.addAll(localRecents.map((e) => e.toString()));
            _recentChats.removeWhere((t) => t == 'AI Agent Project' || t == 'Startup Ideas' || t == 'Python Web Scraper');
            _cloudChatThreads.clear();
            localThreads.forEach((k, v) {
              _cloudChatThreads[k.toString()] = List<Map<String, dynamic>>.from(
                (v as List).map((m) => Map<String, dynamic>.from(m as Map))
              );
            });
          });
        } else {
          setState(() {
            _recentChats.clear();
            _cloudChatThreads.clear();
          });
        }
      } catch (e) {
        debugPrint('Error loading local chats for $email: $e');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _bgAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _bgAnimation = CurvedAnimation(
      parent: _bgAnimationController,
      curve: Curves.linear,
    );
    _micAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _connectWebSocket();

    // 1. Initial guest chats load
    _loadLocalChatsForUser('guest');

    try {
      _googleSignIn.onCurrentUserChanged.listen((account) {
        if (account != null && account.email.isNotEmpty) {
          setState(() {
            _googleUser = account;
            _messages.clear();
            _activeThreadTitle = null;
            _currentWords = '';
          });
          _loadLocalChatsForUser(account.email);
          _fetchUserChatHistory(account.email);
          _notifyBackendEmail(account.email, account.displayName ?? account.email);
        }
      });
      _googleSignIn.signInSilently().catchError((_) => null);
    } catch (e) {
      debugPrint('Google Sign In init silent error: $e');
    }

    if (kIsWeb) {
      try {
        final savedInfoJson = js.context.callMethod('getSavedGoogleAuth', []);
        if (savedInfoJson != null && savedInfoJson.toString().isNotEmpty) {
          final data = jsonDecode(savedInfoJson.toString()) as Map<String, dynamic>;
          final userEmail = data['email']?.toString() ?? '';
          final userName = data['name']?.toString() ?? userEmail;
          if (userEmail.isNotEmpty) {
            setState(() {
              _googleUserMap = {
                'name': userName,
                'email': userEmail,
                'picture': data['picture']?.toString() ?? '',
              };
              _messages.clear();
              _activeThreadTitle = null;
              _currentWords = '';
            });
            _loadLocalChatsForUser(userEmail);
            _fetchUserChatHistory(userEmail);
          }
        }
      } catch (e) {
        debugPrint('Error restoring saved user session: $e');
      }
    }
  }


  Future<void> _fetchUserChatHistory(String email) async {
    if (email.isEmpty) return;
    try {
      final res = await http.get(Uri.parse('$_apiBaseUrl/api/chats/history?email=${Uri.encodeComponent(email)}'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final history = data['history'] as List? ?? [];
        final List<String> titles = [];
        final Map<String, List<Map<String, dynamic>>> threads = {};

        for (var item in history) {
          final String title = item['title']?.toString() ?? 'Chat Session';
          if (title != 'AI Agent Project' && title != 'Startup Ideas' && title != 'Python Web Scraper') {
            final List msgs = item['messages'] as List? ?? [];
            titles.add(title);
            threads[title] = msgs.map((m) => Map<String, dynamic>.from(m as Map)).toList();
          }
        }

        setState(() {
          _recentChats.clear();
          _recentChats.addAll(titles);
          _recentChats.removeWhere((t) => t == 'AI Agent Project' || t == 'Startup Ideas' || t == 'Python Web Scraper');
          _cloudChatThreads = threads;
        });

        if (kIsWeb) {
          try {
            final saveData = {
              'recentChats': _recentChats,
              'threads': _cloudChatThreads
            };
            js.context.callMethod('saveLocalChats', [jsonEncode(saveData), email]);
          } catch (e) {}
        }
      }
    } catch (e) {
      debugPrint('Error fetching user chat history: $e');
    }
  }

  Future<void> _saveCurrentThreadToBackend() async {
    final String userEmail = _activeUserEmail;
    if (_messages.isEmpty) return;

    String title = 'New Chat';
    for (var msg in _messages) {
      if (msg['role'] == 'user' && msg['text'] != null) {
        String t = msg['text'].toString().replaceAll(RegExp(r'^\s*📎\s*\[.*?\]\s*'), '').trim();
        if (t.length > 30) t = '${t.substring(0, 30)}...';
        if (t.isNotEmpty) {
          title = t;
          break;
        }
      }
    }

    setState(() {
      _activeThreadTitle = title;
      _recentChats.remove(title);
      _recentChats.insert(0, title);
      _cloudChatThreads[title] = List.from(_messages);
    });

    if (kIsWeb) {
      try {
        final saveData = {
          'recentChats': _recentChats,
          'threads': _cloudChatThreads
        };
        js.context.callMethod('saveLocalChats', [jsonEncode(saveData), userEmail]);
      } catch (e) {
        debugPrint('Error saving local chats: $e');
      }
    }

    try {
      final payload = {
        'email': userEmail,
        'title': title,
        'messages': _messages.map((m) => {
          'role': m['role'],
          'text': m['text'],
          'ui': m['ui'],
          'ui_type': m['ui_type'],
          'sources': m['sources']
        }).toList()
      };
      await http.post(
        Uri.parse('$_apiBaseUrl/api/chats/save'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
    } catch (e) {
      debugPrint('Error saving chat to backend: $e');
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (kIsWeb) {
      try {
        js.context.callMethod('triggerGoogleAuth', [
          js.allowInterop((dynamic userInfoJson) {
            final data = jsonDecode(userInfoJson.toString()) as Map<String, dynamic>;
            final userEmail = data['email']?.toString() ?? '';
            final userName = data['name']?.toString() ?? userEmail;
            setState(() {
              _googleUserMap = {
                'name': userName,
                'email': userEmail,
                'picture': data['picture']?.toString() ?? '',
              };
              _messages.clear();
              _activeThreadTitle = null;
              _currentWords = '';
              _recentChats.clear();
              _cloudChatThreads.clear();
            });
            _loadLocalChatsForUser(userEmail);
            _fetchUserChatHistory(userEmail);
            _notifyBackendEmail(userEmail, userName);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Welcome, $userName! Your account is connected.')),
              );
            }
          })
        ]);
        return;
      } catch (e) {
        debugPrint('Web GSI Error: $e');
      }
    }

    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        setState(() {
          _googleUser = account;
          _messages.clear();
          _activeThreadTitle = null;
          _currentWords = '';
          _recentChats.clear();
          _cloudChatThreads.clear();
        });
        _loadLocalChatsForUser(account.email);
        _fetchUserChatHistory(account.email);
        _notifyBackendEmail(account.email, account.displayName ?? account.email);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Welcome, ${account.displayName ?? account.email}! Your account is connected.')),
          );
        }
      }
    } catch (e) {
      debugPrint('Google Sign In Error: $e');
    }
  }

  Future<void> _handleGoogleSignOut() async {
    try {
      await _googleSignIn.disconnect();
    } catch (_) {}
    if (kIsWeb) {
      try {
        js.context.callMethod('clearSavedGoogleAuth', []);
      } catch (_) {}
    }
    setState(() {
      _googleUser = null;
      _googleUserMap = null;
      _recentChats.clear();
      _cloudChatThreads = {};
      _messages.clear();
      _activeThreadTitle = null;
    });

    _loadLocalChatsForUser('guest');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signed out from Google. Switched to guest mode.')),
      );
    }
  }

  Future<void> _notifyBackendEmail(String email, String name) async {
    try {
      await http.post(
        Uri.parse('$_apiBaseUrl/api/send-welcome-email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'name': name}),
      );
    } catch (e) {
      debugPrint('Error sending welcome email notification: $e');
    }
  }

  void _connectWebSocket() {
    try {
      _wsChannel = WebSocketChannel.connect(
        Uri.parse('$_wsBaseUrl/ws/chat/$_sessionId'),
      );
      _wsChannel!.stream.listen(
        (data) => _handleWebSocketMessage(data),
        onError: (err) => debugPrint('WS Error: $err'),
        onDone: () => debugPrint('WS Closed'),
      );
    } catch (e) {
      debugPrint('WS Connection failed: $e');
    }
  }

  void _handleWebSocketMessage(dynamic messageData) {
    try {
      final data = jsonDecode(messageData);
      final type = data['type'];

      if (type == 'start') {
        setState(() {
          _isTyping = true;
          _activeToolStatus = 'Thinking...';
        });
      } else if (type == 'tool_start') {
        final tool = data['tool'] ?? 'Google Search';
        setState(() {
          _activeToolStatus = '🌐 Searching with $tool...';
        });
      } else if (type == 'tool_end') {
        final sources = data['sources'] as List? ?? [];
        setState(() {
          _activeToolStatus = 'Synthesizing response...';
          _currentSources = sources.map((s) => {
            'title': s['title'].toString(),
            'url': s['url'].toString()
          }).toList();
        });
      } else if (type == 'token') {
        final token = data['content'] ?? '';
        if (token.isNotEmpty) {
          setState(() {
            _currentWords += token;
            _activeToolStatus = '';
            _parseUiTags();
            if (_messages.isNotEmpty && _messages.last['role'] == 'ai') {
              _messages.last['text'] = _currentWords;
              _messages.last['sources'] = List<Map<String, String>>.from(_currentSources);
            } else {
              _messages.add({
                'role': 'ai',
                'text': _currentWords,
                'ui': null,
                'ui_type': null,
                'sources': List<Map<String, String>>.from(_currentSources)
              });
            }
          });
          _scrollToBottom();
        }
      } else if (type == 'done') {
        setState(() {
          _isTyping = false;
          _activeToolStatus = '';
          if (_currentWords.isNotEmpty) {
            if (_messages.isNotEmpty && _messages.last['role'] == 'ai') {
              _messages.last['text'] = _currentWords;
              _messages.last['sources'] = List<Map<String, String>>.from(_currentSources);
            } else {
              _messages.add({
                'role': 'ai',
                'text': _currentWords,
                'ui': null,
                'ui_type': null,
                'sources': List<Map<String, String>>.from(_currentSources)
              });
            }
            _currentWords = '';
          }
        });
        _saveCurrentThreadToBackend();
      }

    } catch (e) {
      debugPrint('Error parsing WS frame: $e');
    }
  }

  void _startNewChat() {
    setState(() {
      _messages.clear();
      _currentWords = '';
      _activeToolStatus = '';
      _currentSources = [];
      _attachedFileName = null;
      _activeThreadTitle = null;
      _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    });
    _wsChannel?.sink.close();
    _connectWebSocket();
  }

  void _loadThread(String title) {
    final matchingKey = _cloudChatThreads.keys.firstWhere(
      (k) => k == title || k.trim() == title.trim() || k.startsWith(title) || title.startsWith(k),
      orElse: () => '',
    );

    if (matchingKey.isNotEmpty && _cloudChatThreads[matchingKey]!.isNotEmpty) {
      setState(() {
        _activeThreadTitle = matchingKey;
        _messages.clear();
        _messages.addAll(
          _cloudChatThreads[matchingKey]!.map((m) => Map<String, dynamic>.from(m))
        );
        _currentWords = '';
        _activeToolStatus = '';
        _currentSources = [];
      });
    }
  }





  Future<void> _sendMessage([String? overrideText]) async {
    final text = overrideText ?? _controller.text.trim();
    if (text.isEmpty && _attachedFileName == null) return;

    String fullMessage = text;
    if (_attachedFileName != null) {
      final extracted = (_attachedFileContent != null && _attachedFileContent!.isNotEmpty)
          ? _attachedFileContent!
          : '[Attached file: $_attachedFileName]';
      final fileContext = '''--- BEGIN ATTACHED FILE CONTEXT ---
File Name: $_attachedFileName
Extracted File Content:
=====================================================
$extracted
--- END ATTACHED FILE CONTEXT ---''';

      fullMessage = text.isNotEmpty
          ? '$fileContext\n\n[Attached File: $_attachedFileName]\nUser Question/Instruction: $text'
          : '$fileContext\n\n[Attached File: $_attachedFileName]\nPlease analyze, extract key insights from, and explain this attached file thoroughly.';
    }

    final displayUserText = _attachedFileName != null 
        ? '📎 [Attached: $_attachedFileName]\n${text.isNotEmpty ? text : 'Analyze document'}' 
        : text;

    setState(() {
      if (_activeThreadTitle == null) {
        _messages.clear();
      }
      _messages.add({'role': 'user', 'text': displayUserText});
      _messages.add({
        'role': 'ai',
        'text': '',
        'ui': null,
        'ui_type': null,
        'sources': <Map<String, String>>[]
      });

      _isTyping = true;
      _controller.clear();
      _attachedFileName = null;
      _attachedFileContent = null;
      _isUploadingFile = false;
      _currentWords = '';
      _currentSources = [];
      _activeToolStatus = 'Connecting to Dora...';
    });
    _scrollToBottom();
    _saveCurrentThreadToBackend();


    // Use WebSocket
    if (_wsChannel != null) {
      try {
        _wsChannel!.sink.add(jsonEncode({
          'message': fullMessage,
          'model': _selectedModel,
          'deep_research': _isDeepResearch,
        }));
        return;
      } catch (e) {
        debugPrint('WS failed, fallback: $e');
      }
    }

    // Fallback HTTP
    var client = http.Client();
    try {
      var request = http.Request('POST', Uri.parse('$_apiBaseUrl/chat'));
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'message': fullMessage,
        'session_id': _sessionId,
        'model': _selectedModel
      });
      var response = await client.send(request);

      await for (var chunk in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (chunk.startsWith('data: ')) {
          var jsonStr = chunk.substring(6).trim();
          if (jsonStr == '[DONE]') break;
          try {
            var decoded = jsonDecode(jsonStr);
            var content = decoded['content'] ?? '';
            if (content.isNotEmpty) {
              setState(() {
                _currentWords += content;
                _activeToolStatus = '';
                _parseUiTags();
              });
              _scrollToBottom();
            }
          } catch (e) {}
        }
      }
    } catch (e) {
      setState(() => _messages.last['text'] = "Error connecting to Dora: $e");
    } finally {
      client.close();
      setState(() {
        _isTyping = false;
        _activeToolStatus = '';
      });
    }
  }

  void _parseUiTags() {
    final text = _currentWords;

    // 1. Weather Card
    final weatherRegex = RegExp(r'\[UI:WEATHER_CARD\](\{.*?\})(?:\[\/UI:WEATHER_CARD\]|$)', dotAll: true);
    final weatherMatch = weatherRegex.firstMatch(text);
    if (weatherMatch != null) {
      try {
        final weatherData = jsonDecode(weatherMatch.group(1)!);
        final cleanText = text.replaceAll(weatherRegex, '').replaceAll(RegExp(r'\[UI:.*?\]'), '').trim();
        setState(() {
          _messages.last['text'] = cleanText;
          _messages.last['ui'] = weatherData;
          _messages.last['ui_type'] = 'WEATHER';
          _messages.last['sources'] = List<Map<String, String>>.from(_currentSources);
        });
        return;
      } catch (e) {}
    }

    // 2. Task Checklist Card
    final taskRegex = RegExp(r'\[UI:TASK_CARD\](\{.*?\})(?:\[\/UI:TASK_CARD\]|$)', dotAll: true);
    final taskMatch = taskRegex.firstMatch(text);
    if (taskMatch != null) {
      try {
        final taskData = jsonDecode(taskMatch.group(1)!);
        final cleanText = text.replaceAll(taskRegex, '').replaceAll(RegExp(r'\[UI:.*?\]'), '').trim();
        setState(() {
          _messages.last['text'] = cleanText;
          _messages.last['ui'] = taskData;
          _messages.last['ui_type'] = 'TASK';
          _messages.last['sources'] = List<Map<String, String>>.from(_currentSources);
        });
        return;
      } catch (e) {}
    }

    // 3. Chart Card
    final chartRegex = RegExp(r'\[UI:CHART_CARD\](\{.*?\})(?:\[\/UI:CHART_CARD\]|$)', dotAll: true);
    final chartMatch = chartRegex.firstMatch(text);
    if (chartMatch != null) {
      try {
        final chartData = jsonDecode(chartMatch.group(1)!);
        final cleanText = text.replaceAll(chartRegex, '').replaceAll(RegExp(r'\[UI:.*?\]'), '').trim();
        setState(() {
          _messages.last['text'] = cleanText;
          _messages.last['ui'] = chartData;
          _messages.last['ui_type'] = 'CHART';
          _messages.last['sources'] = List<Map<String, String>>.from(_currentSources);
        });
        return;
      } catch (e) {}
    }

    final cleanText = text.replaceAll(RegExp(r'\[UI:.*?\]\{.*?\}(?:\[\/UI:.*?\]|$)'), '').trim();
    setState(() {
      _messages.last['text'] = cleanText.isNotEmpty ? cleanText : text;
      _messages.last['sources'] = List<Map<String, String>>.from(_currentSources);
    });
  }

  Future<void> _modifyResponse(int index, String instruction) async {
    final originalText = _messages[index]['text'];
    if (originalText == null || originalText.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Rewriting response ($instruction)...'), duration: const Duration(seconds: 2)),
    );

    try {
      final res = await http.post(
        Uri.parse('$_apiBaseUrl/chat/modify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': originalText, 'instruction': instruction}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _messages[index]['text'] = data['modified_text'];
        });
      }
    } catch (e) {
      debugPrint('Error modifying response: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _startListening() async {
    bool available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' && _isListening) {
          setState(() => _isListening = false);
          if (_controller.text.isNotEmpty) _sendMessage();
        }
      },
      onError: (error) => setState(() => _isListening = false),
    );

    if (available) {
      setState(() => _isListening = true);
      _speech.listen(onResult: (result) {
        setState(() {
          _controller.text = result.recognizedWords;
        });
      });
    }
  }

  void _stopListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
    if (_controller.text.isNotEmpty) _sendMessage();
  }

  Future<void> _pickAndAttachFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.any,
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final fileName = file.name;
        final bytes = file.bytes;

        if (bytes == null || bytes.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not read file data for $fileName')),
            );
          }
          return;
        }

        final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
        final textExts = ['txt', 'csv', 'json', 'py', 'dart', 'js', 'ts', 'html', 'css', 'md', 'yaml', 'yml', 'xml', 'sql', 'sh', 'java', 'cpp', 'c', 'h', 'log', 'env'];

        if (textExts.contains(ext)) {
          String textContent;
          try {
            textContent = utf8.decode(bytes, allowMalformed: true);
          } catch (_) {
            textContent = latin1.decode(bytes);
          }
          setState(() {
            _attachedFileName = fileName;
            _attachedFileContent = textContent;
            _isUploadingFile = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFF1E2028),
                content: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Color(0xFF6366F1)),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Attached file: $fileName (${bytes.length} bytes)', style: const TextStyle(color: Colors.white))),
                  ],
                ),
              ),
            );
          }
        } else {
          // Upload PDF, Image, or binary document to backend for extraction
          setState(() {
            _isUploadingFile = true;
            _attachedFileName = fileName;
            _attachedFileContent = null;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 2),
                backgroundColor: const Color(0xFF1E2028),
                content: Row(
                  children: [
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1))),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Uploading & analyzing $fileName...', style: const TextStyle(color: Colors.white))),
                  ],
                ),
              ),
            );
          }
          try {
            var request = http.MultipartRequest('POST', Uri.parse('$_apiBaseUrl/api/upload-document'));
            request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
            var streamedResponse = await request.send();
            var res = await http.Response.fromStream(streamedResponse);
            if (res.statusCode == 200) {
              final data = jsonDecode(res.body);
              final extracted = data['text']?.toString() ?? '[File attached: $fileName]';
              setState(() {
                _attachedFileContent = extracted;
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFF1E2028),
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.greenAccent),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Ready: $fileName analyzed and attached!', style: const TextStyle(color: Colors.white))),
                      ],
                    ),
                  ),
                );
              }
            } else {
              setState(() {
                _attachedFileContent = '[Attached File: $fileName (${bytes.length} bytes)]';
              });
            }
          } catch (e) {
            setState(() {
              _attachedFileContent = '[Attached File: $fileName (${bytes.length} bytes)]';
            });
            debugPrint('Upload error: $e');
          } finally {
            setState(() => _isUploadingFile = false);
          }
        }
      }
    } catch (e) {
      debugPrint('File picker error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File picker error: $e')),
        );
      }
    }
  }


  @override
  void dispose() {
    _wsChannel?.sink.close();
    _micAnimationController.dispose();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      drawer: Drawer(
        backgroundColor: const Color(0xFF111318),
        surfaceTintColor: Colors.transparent,
        child: SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: Color(0xFF1F222E), width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.6), blurRadius: 12, spreadRadius: 1),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            'dora_ai_logo.png',
                            width: 36,
                            height: 36,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, err, stack) => Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.auto_awesome, size: 22, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text('Dora AI', style: GoogleFonts.inter(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 0.5)),

                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _startNewChat();
                      },
                      icon: const Icon(Icons.add_rounded, color: Colors.white),
                      label: Text('New Chat', style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        minimumSize: const Size(double.infinity, 48),
                        alignment: Alignment.centerLeft,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 20, top: 20, bottom: 8),
                  child: Text('RECENT CHATS', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ),
                Expanded(
                  child: _recentChats.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          child: Text(
                            'No recent chats yet.\nStart asking questions to build your history!',
                            style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.4),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _recentChats.length,
                          itemBuilder: (context, index) {
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white54, size: 18),
                              title: Text(_recentChats[index], style: GoogleFonts.inter(color: Colors.white70, fontSize: 14), overflow: TextOverflow.ellipsis),
                              hoverColor: const Color(0xFF1E2028),
                              onTap: () {
                                Navigator.pop(context);
                                _loadThread(_recentChats[index]);
                              },
                            );
                          },
                        ),
                ),

                const Divider(color: Color(0xFF1F222E), height: 1),

                Container(
                  padding: const EdgeInsets.all(16),
                  color: const Color(0xFF16181D),
                  child: (_googleUser != null || _googleUserMap != null)
                      ? Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xFF6366F1),
                              backgroundImage: (_googleUser?.photoUrl != null)
                                  ? NetworkImage(_googleUser!.photoUrl!)
                                  : (_googleUserMap?['picture'] != null && _googleUserMap!['picture']!.isNotEmpty
                                      ? NetworkImage(_googleUserMap!['picture']!)
                                      : null),
                              child: (_googleUser?.photoUrl == null && (_googleUserMap?['picture'] == null || _googleUserMap!['picture']!.isEmpty))
                                  ? Text(
                                      (_googleUser?.displayName ?? _googleUserMap?['name'] ?? 'G')[0].toUpperCase(),
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_googleUser?.displayName ?? _googleUserMap?['name'] ?? 'Google User', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 2),
                                  Text(_googleUser?.email ?? _googleUserMap?['email'] ?? '', style: GoogleFonts.inter(color: Colors.greenAccent, fontSize: 11), overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18),
                              tooltip: 'Sign out of Google',
                              onPressed: _handleGoogleSignOut,
                            ),
                          ],
                        )
                      : InkWell(
                          onTap: _handleGoogleSignIn,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFF4285F4), Color(0xFF34A853)]),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.g_mobiledata_rounded, color: Colors.white, size: 24),
                                const SizedBox(width: 6),
                                Text(
                                  'Sign in with Google',
                                  style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
      appBar: AppBar(
        title: const SizedBox.shrink(),
        actions: [
          (_googleUser != null || _googleUserMap != null)
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 10),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundImage: (_googleUser?.photoUrl != null)
                            ? NetworkImage(_googleUser!.photoUrl!)
                            : (_googleUserMap?['picture'] != null && _googleUserMap!['picture']!.isNotEmpty
                                ? NetworkImage(_googleUserMap!['picture']!)
                                : null),
                        child: (_googleUser?.photoUrl == null && (_googleUserMap?['picture'] == null || _googleUserMap!['picture']!.isEmpty))
                            ? Text((_googleUser?.displayName ?? _googleUserMap?['name'] ?? 'G')[0].toUpperCase())
                            : null,
                      ),
                      const SizedBox(width: 6),
                      Text(_googleUser?.displayName ?? _googleUserMap?['name'] ?? 'Google User', style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: OutlinedButton.icon(
                    onPressed: _handleGoogleSignIn,
                    icon: const Icon(Icons.g_mobiledata_rounded, color: Colors.blueAccent, size: 20),
                    label: const Text('Google Sign-In', style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF4285F4), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                ),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: ChoiceChip(
              avatar: const Icon(Icons.science_outlined, size: 14, color: Colors.cyanAccent),
              label: const Text('Deep Research', style: TextStyle(fontSize: 12)),
              selected: _isDeepResearch,
              selectedColor: const Color(0xFF6366F1),
              backgroundColor: const Color(0xFF18191E),
              labelStyle: TextStyle(color: _isDeepResearch ? Colors.white : Colors.white70, fontWeight: _isDeepResearch ? FontWeight.bold : FontWeight.normal),
              onSelected: (val) => setState(() => _isDeepResearch = val),
            ),
          ),

          const SizedBox(width: 4),

          IconButton(
            icon: const Icon(Icons.add_comment_outlined, color: Colors.white70),
            tooltip: 'New Chat',
            onPressed: _startNewChat,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: MouseRegion(
        onHover: (event) => setState(() => _cursorPosition = event.localPosition),
        child: AnimatedBuilder(
          animation: _bgAnimationController,
          builder: (context, child) {
            double val = _bgAnimationController.value;
            double angle = val * 2 * math.pi;

            // AI-State Dynamic Colors
            Color orb1Color = _isDeepResearch
                ? const Color(0xFFEC4899)
                : (_isTyping ? const Color(0xFF06B6D4) : const Color(0xFF8B5CF6));
            Color orb2Color = _isTyping ? const Color(0xFF3B82F6) : const Color(0xFF06B6D4);

            double x1 = math.cos(angle) * 160;
            double y1 = math.sin(angle) * 120;
            double x2 = math.sin(angle * 1.2) * 180;
            double y2 = math.cos(angle * 1.2) * 130;
            double x3 = math.cos(angle * 0.8) * 140;
            double y3 = math.sin(angle * 0.8) * 140;

            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(math.cos(angle * 0.5), math.sin(angle * 0.5)),
                  end: Alignment(-math.cos(angle * 0.5), -math.sin(angle * 0.5)),
                  colors: const [
                    Color(0xFF0D0D12),
                    Color(0xFF141226),
                    Color(0xFF0F0D1A),
                    Color(0xFF0D0D12),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  // Floating Orb 1 (AI-State Dynamic Color)
                  Positioned(
                    top: 40 + y1,
                    right: 60 + x1,
                    child: Container(
                      width: 520,
                      height: 520,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            orb1Color.withOpacity(0.44),
                            const Color(0xFF6366F1).withOpacity(0.18),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Floating Orb 2
                  Positioned(
                    bottom: 20 + y2,
                    left: 40 + x2,
                    child: Container(
                      width: 540,
                      height: 540,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            orb2Color.withOpacity(0.38),
                            const Color(0xFF3B82F6).withOpacity(0.15),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Floating Orb 3
                  Positioned(
                    top: 150 + y3,
                    left: 100 + x3,
                    child: Container(
                      width: 480,
                      height: 480,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFFEC4899).withOpacity(0.34),
                            const Color(0xFF8B5CF6).withOpacity(0.12),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // INTERACTIVE MOUSE CURSOR SPOTLIGHT ORB
                  Positioned(
                    left: _cursorPosition.dx - 220,
                    top: _cursorPosition.dy - 220,
                    child: Container(
                      width: 440,
                      height: 440,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF8B5CF6).withOpacity(0.24),
                            const Color(0xFF06B6D4).withOpacity(0.08),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // FLOATING COSMIC DUST PARTICLES
                  Positioned.fill(
                    child: CustomPaint(
                      painter: CosmicParticlePainter(val),
                    ),
                  ),

                  child!,
                ],
              ),
            );
          },
        child: Stack(
          children: [
            Positioned(
            top: -80,
            left: MediaQuery.of(context).size.width * 0.15,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF6366F1).withOpacity(0.65),
                    const Color(0xFF8B5CF6).withOpacity(0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 60,
            right: MediaQuery.of(context).size.width * 0.08,
            child: Container(
              width: 550,
              height: 550,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFEC4899).withOpacity(0.55),
                    const Color(0xFF8B5CF6).withOpacity(0.30),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: MediaQuery.of(context).size.width * 0.35,
            child: Container(
              width: 450,
              height: 450,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF3B82F6).withOpacity(0.45),
                    const Color(0xFF6366F1).withOpacity(0.20),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(color: Colors.transparent),
            ),
          ),

          // Layer 1: Main Content Row
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    // Empty State Viewport: Ultra-Sleek Dark Mode Scrolling Landing Showcase
                    if (_messages.isEmpty)
                      Expanded(
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (scrollNotification) {
                            return true;
                          },
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 1. HERO SHOWCASE SECTION (Staggered Animation)
                                ScrollRevealWidget(
                                  delayMs: 100,
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        const SizedBox(height: 30),
                                        // Glowing Central Emblem
                                        Container(
                                          width: 64,
                                          height: 64,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: const LinearGradient(
                                              colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF8B5CF6).withOpacity(0.5),
                                                blurRadius: 24,
                                                spreadRadius: 4,
                                              ),
                                            ],
                                          ),
                                          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 32),
                                        ),
                                        const SizedBox(height: 20),
                                        Text(
                                          'Welcome to Dora AI',
                                          style: GoogleFonts.inter(
                                            color: const Color(0xFF94A3B8),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'How Can I Assist You?',
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontSize: 34,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 36),
                                        // 3 Horizontal Translucent Starter Cards
                                        Wrap(
                                          spacing: 16,
                                          runSpacing: 16,
                                          alignment: WrapAlignment.center,
                                          children: [
                                            _buildEchoStarterCard(
                                              icon: Icons.playlist_add_check_rounded,
                                              title: 'Write a todo list for my day',
                                              prompt: 'Create a structured action plan and todo list for a productive workday.',
                                            ),
                                            _buildEchoStarterCard(
                                              icon: Icons.code_rounded,
                                              title: 'Build a Python web scraper',
                                              prompt: 'Write a complete Python script using BeautifulSoup to scrape website content.',
                                            ),
                                            _buildEchoStarterCard(
                                              icon: Icons.analytics_outlined,
                                              title: 'Generate a data comparison chart',
                                              prompt: 'Compare top programming languages in 2026 and render a data comparison chart.',
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 40),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text('QUICK CONSULTATION SUGGESTIONS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8), letterSpacing: 1.5)),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    _buildSuggestionChip(
                                      icon: Icons.lightbulb_outline,
                                      iconColor: Colors.amberAccent,
                                      title: 'Brainstorm ideas',
                                      subtitle: 'Generate startup features & naming concepts',
                                      prompt: 'Brainstorm 5 innovative features for an AI Chatbot application.',
                                    ),
                                    _buildSuggestionChip(
                                      icon: Icons.code,
                                      iconColor: Colors.blueAccent,
                                      title: 'Understand code',
                                      subtitle: 'Write & debug Python script for web scraping',
                                      prompt: 'Write a Python script using BeautifulSoup to scrape article titles.',
                                    ),
                                    _buildSuggestionChip(
                                      icon: Icons.summarize_outlined,
                                      iconColor: Colors.greenAccent,
                                      title: 'Summarize text',
                                      subtitle: 'Condense complex articles into bullet points',
                                      prompt: 'Explain Quantum Computing in 3 bullet points for a 10-year-old.',
                                    ),
                                    _buildSuggestionChip(
                                      icon: Icons.edit_note,
                                      iconColor: Colors.purpleAccent,
                                      title: 'Draft an email',
                                      subtitle: 'Create a professional follow-up template',
                                      prompt: 'Draft a polite follow-up email after a tech job interview.',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      // Chat Stream Messages List
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final isUser = msg['role'] == 'user';

                            return Align(
                              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
                                margin: const EdgeInsets.only(bottom: 20),
                                child: Column(
                                  crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                                      children: [
                                        if (!isUser) ...[
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: LinearGradient(colors: [Color(0xFF4285F4), Color(0xFF9B51E0)]),
                                            ),
                                            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                                          ),
                                          const SizedBox(width: 12),
                                        ],
                                        Flexible(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                            decoration: BoxDecoration(
                                              color: isUser ? const Color(0xFF1E2028) : const Color(0xFF16181D),
                                              borderRadius: BorderRadius.circular(16),
                                              border: Border.all(
                                                color: isUser ? const Color(0xFF6366F1).withOpacity(0.35) : const Color(0xFF2A2D3A),
                                                width: 1,
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                if (msg['text'] != null && msg['text'].isNotEmpty) ...[
                                                  if (isUser)
                                                    Text(
                                                      msg['text'],
                                                      style: GoogleFonts.inter(color: Colors.white, fontSize: 15, height: 1.5),
                                                    )
                                                  else
                                                    MarkdownBody(
                                                      data: msg['text'],
                                                      selectable: true,
                                                      styleSheet: MarkdownStyleSheet(
                                                        p: GoogleFonts.inter(color: Colors.white, fontSize: 15, height: 1.6),
                                                        h1: GoogleFonts.inter(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                                                        h2: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                                        h3: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                                                        code: GoogleFonts.jetBrainsMono(color: Colors.amberAccent, backgroundColor: const Color(0xFF111318), fontSize: 13),
                                                        codeblockDecoration: BoxDecoration(
                                                          color: const Color(0xFF111318),
                                                          borderRadius: BorderRadius.circular(10),
                                                          border: Border.all(color: const Color(0xFF2A2D3A), width: 1),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                                if (msg['ui'] != null) ...[
                                                  const SizedBox(height: 14),
                                                  if (msg['ui_type'] == 'WEATHER') WeatherCard(weatherData: msg['ui']),
                                                  if (msg['ui_type'] == 'TASK') TaskChecklistCard(taskData: msg['ui']),
                                                  if (msg['ui_type'] == 'CHART') ChartCard(chartData: msg['ui']),
                                                ],
                                                if (!isUser && msg['sources'] != null && (msg['sources'] as List).isNotEmpty) ...[
                                                  const SizedBox(height: 14),
                                                  Text('SOURCES & CITATIONS', style: GoogleFonts.inter(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                                                  const SizedBox(height: 6),
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 8,
                                                    children: (msg['sources'] as List).map((src) {
                                                      return Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFF1E2028),
                                                          borderRadius: BorderRadius.circular(12),
                                                          border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            const Icon(Icons.link_rounded, color: Color(0xFF6366F1), size: 12),
                                                            const SizedBox(width: 4),
                                                            Text(
                                                              src['title'].toString(),
                                                              style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    }).toList(),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (isUser) ...[
                                          const SizedBox(width: 8),
                                          const CircleAvatar(
                                            radius: 14,
                                            backgroundColor: Color(0xFF282A2C),
                                            child: Icon(Icons.person, color: Colors.white70, size: 16),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (!isUser && msg['text'] != null && msg['text'].isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.copy_outlined, size: 16, color: Colors.white38),
                                            tooltip: 'Copy response',
                                            onPressed: () {
                                              Clipboard.setData(ClipboardData(text: msg['text']));
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard!')));
                                            },
                                          ),
                                          IconButton(
                                            icon: Icon(_isSpeaking ? Icons.volume_off : Icons.volume_up_outlined, size: 16, color: _isSpeaking ? Colors.amberAccent : Colors.white38),
                                            tooltip: _isSpeaking ? 'Stop reading' : 'Read aloud (TTS)',
                                            onPressed: () => _speakText(msg['text']),
                                          ),
                                          if (msg['text'].contains('```'))
                                            IconButton(
                                              icon: const Icon(Icons.space_dashboard_outlined, size: 16, color: Colors.blueAccent),
                                              tooltip: 'Open in Code Canvas',
                                              onPressed: () {
                                                final codeMatches = RegExp(r'```(?:\w+)?\n([\s\S]*?)```').allMatches(msg['text']);
                                                if (codeMatches.isNotEmpty) {
                                                  final codeSnippet = codeMatches.first.group(1);
                                                  if (codeSnippet != null) {
                                                    _openCanvas('Generated Code', codeSnippet, 'python');
                                                  }
                                                }
                                              },
                                            ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    // Active Tool Status Badge
                    if (_isTyping || _activeToolStatus.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 24, bottom: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1F20),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.35)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _activeToolStatus.isNotEmpty ? _activeToolStatus : 'Dora is thinking...',
                                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // Ultra-Sleek Dark Mode Floating Prompt Container
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF18191E),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.35), width: 1.5),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.1), blurRadius: 16, spreadRadius: 2, offset: const Offset(0, 4)),
                          BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_attachedFileName != null)
                            Container(
                              margin: const EdgeInsets.only(left: 12, top: 4, bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF22242C),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _isUploadingFile ? Colors.amberAccent.withOpacity(0.5) : const Color(0xFF6366F1).withOpacity(0.5),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isUploadingFile)
                                    const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.amberAccent))
                                  else
                                    const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    _attachedFileName! + (_isUploadingFile ? ' (extracting...)' : ''),
                                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(width: 6),
                                  InkWell(
                                    onTap: () => setState(() {
                                      _attachedFileName = null;
                                      _attachedFileContent = null;
                                      _isUploadingFile = false;
                                    }),
                                    child: const Icon(Icons.close_rounded, color: Colors.white38, size: 14),
                                  ),
                                ],
                              ),
                            ),
                          Row(
                            children: [
                              IconButton(
                                icon: _isUploadingFile
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1)))
                                    : const Icon(Icons.add_circle_outline_rounded, color: Colors.white70),
                                tooltip: 'Attach real image, PDF, document, or code file',
                                onPressed: _isUploadingFile ? null : _pickAndAttachFile,
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _controller,
                                  style: const TextStyle(color: Colors.white, fontSize: 15),
                                  decoration: InputDecoration(
                                    hintText: _isListening ? 'Listening...' : 'Ask Dora...',
                                    hintStyle: TextStyle(color: _isListening ? Colors.redAccent : Colors.white38),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                  ),
                                  onSubmitted: (_) => _sendMessage(),
                                ),
                              ),
                              ScaleTransition(
                                scale: _isListening 
                                    ? Tween<double>(begin: 1.0, end: 1.25).animate(_micAnimationController)
                                    : const AlwaysStoppedAnimation(1.0),
                                child: IconButton(
                                  icon: Icon(
                                    _isListening ? Icons.mic : Icons.mic_none_rounded,
                                    color: _isListening ? Colors.redAccent : Colors.white70,
                                  ),
                                  tooltip: 'Voice search',
                                  onPressed: _isListening ? _stopListening : _startListening,
                                ),
                              ),
                              const SizedBox(width: 4),
                              GlowingHoverButton(
                                glowColor: const Color(0xFF6366F1),
                                borderRadius: BorderRadius.circular(30),
                                onPressed: _isTyping ? null : () => _sendMessage(),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                                  ),
                                  child: const Icon(Icons.arrow_upward_rounded, size: 20, color: Colors.white),
                                ),
                              ),

                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            ],
          ),
        ],
      ),
    ),
   ),
  );
}


  Widget _buildLeonardoCard({
    required String title,
    required LinearGradient gradient,
    required IconData assetIcon,
    required String prompt,
  }) {
    return InkWell(
      onTap: () => _sendMessage(prompt),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 220,
        height: 140,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 6)),
          ],
        ),
        child: Stack(
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.2,
              ),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(assetIcon, color: Colors.white, size: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildPillarCard({
    required double width,
    required IconData icon,
    required Color iconColor,
    required String tag,
    required String title,
    required String description,
    required String actionText,
    required String prompt,
  }) {
    return StatefulBuilder(
      builder: (context, setCardState) {
        bool isHovered = false;

        return MouseRegion(
          onEnter: (_) => setCardState(() => isHovered = true),
          onExit: (_) => setCardState(() => isHovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            width: width,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isHovered ? const Color(0xFF1C1E2B).withOpacity(0.90) : const Color(0xFF141620).withOpacity(0.75),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isHovered ? iconColor : const Color(0xFF6366F1).withOpacity(0.45),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isHovered ? iconColor.withOpacity(0.35) : const Color(0xFF6366F1).withOpacity(0.12),
                  blurRadius: isHovered ? 24 : 16,
                  spreadRadius: isHovered ? 2 : 0,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Bento Graphic Preview Header Container
                Container(
                  height: 100,
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B0C10).withOpacity(0.8),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: iconColor.withOpacity(0.3), width: 1),
                  ),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: iconColor.withOpacity(0.2),
                        boxShadow: [
                          BoxShadow(color: iconColor.withOpacity(0.4), blurRadius: 16, spreadRadius: 2),
                        ],
                      ),
                      child: Icon(icon, color: iconColor, size: 28),
                    ),
                  ),
                ),
                Text(
                  tag,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: iconColor,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF94A3B8),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                InkWell(
                  onTap: () => _sendMessage(prompt),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        actionText,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: iconColor,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, size: 14, color: iconColor),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  Widget _buildTelemetryCard(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF16181D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2D3A), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 4),
          Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
        ],
      ),
    );
  }


  Widget _buildEditorialCard({
    required double width,
    required String category,
    required String title,
    required String action,
    required String prompt,
    IconData assetIcon = Icons.auto_awesome_mosaic_outlined,
  }) {
    return StatefulBuilder(
      builder: (context, setCardState) {
        bool isHovered = false;

        return MouseRegion(
          onEnter: (_) => setCardState(() => isHovered = true),
          onExit: (_) => setCardState(() => isHovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            width: width,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isHovered ? const Color(0xFFFAFAFA) : const Color(0xFFFFFFFF),
              border: Border.all(color: isHovered ? const Color(0xFF111111) : const Color(0xFFEAEAEA), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Low-Contrast Desaturated Image Asset Frame Container
                Container(
                  height: 120,
                  width: double.infinity,
                  color: const Color(0xFFF5F5F5),
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Center(
                    child: Icon(assetIcon, color: const Color(0xFF888888), size: 36),
                  ),
                ),
                Text(
                  category,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF888888),
                    letterSpacing: 2.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF111111),
                    height: 1.25,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 20),
                InkWell(
                  onTap: () => _sendMessage(prompt),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        action,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF111111),
                          letterSpacing: 1.4,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward_rounded, size: 12, color: Color(0xFF111111)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }








  Widget _buildCanvasPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF14151A),
        border: Border(left: BorderSide(color: Colors.white10, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Canvas Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF18191E),
            child: Row(
              children: [
                const Icon(Icons.code_rounded, color: Color(0xFF6366F1), size: 18),
                const SizedBox(width: 8),
                Text(_activeCanvasTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy_outlined, color: Colors.white54, size: 16),
                  tooltip: 'Copy Code',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _activeCanvasCode));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied canvas code!')));
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 16),
                  onPressed: () => setState(() => _showCanvas = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                _activeCanvasCode,
                style: const TextStyle(color: Colors.amberAccent, fontFamily: 'monospace', fontSize: 13, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }


    Widget _buildEchoStarterCard({required IconData icon, required String title, required String prompt}) {
    return InkWell(
      onTap: () => _sendMessage(prompt),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF16181D).withOpacity(0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            Icon(icon, color: const Color(0xFF6366F1), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionChip({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String prompt,
  }) {
    return StatefulBuilder(
      builder: (context, setChipState) {
        bool isHovered = false;

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setChipState(() => isHovered = true),
          onExit: (_) => setChipState(() => isHovered = false),
          child: GestureDetector(
            onTap: () => _sendMessage(prompt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              transform: Matrix4.identity()..scale(isHovered ? 1.05 : 1.0),
              transformAlignment: Alignment.center,
              width: 220,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isHovered ? const Color(0xFF242630) : const Color(0xFF1E1F20),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isHovered ? iconColor : Colors.white10,
                  width: isHovered ? 1.5 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: iconColor.withOpacity(isHovered ? 0.55 : 0.08),
                    blurRadius: isHovered ? 20 : 8,
                    spreadRadius: isHovered ? 2 : 0,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: iconColor, size: 24),
                  const SizedBox(height: 12),
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class GlowingHoverButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final Color glowColor;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;

  const GlowingHoverButton({
    super.key,
    required this.child,
    this.onPressed,
    this.glowColor = const Color(0xFF6366F1),
    this.borderRadius,
    this.padding,
  });

  @override
  State<GlowingHoverButton> createState() => _GlowingHoverButtonState();
}

class _GlowingHoverButtonState extends State<GlowingHoverButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(24);
    return MouseRegion(
      cursor: widget.onPressed != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          transform: Matrix4.identity()..scale(_isHovered ? 1.05 : 1.0),
          transformAlignment: Alignment.center,
          padding: widget.padding,
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: widget.glowColor.withOpacity(0.65),
                      blurRadius: 20,
                      spreadRadius: 3,
                      offset: const Offset(0, 2),
                    ),
                    BoxShadow(
                      color: widget.glowColor.withOpacity(0.35),
                      blurRadius: 36,
                      spreadRadius: 6,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: widget.glowColor.withOpacity(0.12),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                  ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}


// ==========================================
// GENERATIVE UI WIDGET 1: WEATHER CARD
// ==========================================
class WeatherCard extends StatelessWidget {
  final dynamic weatherData;
  const WeatherCard({super.key, required this.weatherData});

  @override
  Widget build(BuildContext context) {
    String location = weatherData['location'] ?? 'Unknown';
    String temp = weatherData['temp'] ?? '--';
    String condition = weatherData['condition'] ?? 'Clear';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1E3C72), Color(0xFF2A5298)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.wb_sunny, size: 36, color: Colors.amberAccent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(location, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('$temp • $condition', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// GENERATIVE UI WIDGET 2: TASK CHECKLIST CARD
// ==========================================
class TaskChecklistCard extends StatefulWidget {
  final dynamic taskData;
  const TaskChecklistCard({super.key, required this.taskData});

  @override
  State<TaskChecklistCard> createState() => _TaskChecklistCardState();
}

class _TaskChecklistCardState extends State<TaskChecklistCard> {
  late List<bool> _checkedState;

  @override
  void initState() {
    super.initState();
    List tasks = widget.taskData['tasks'] ?? [];
    _checkedState = List.filled(tasks.length, false);
  }

  @override
  Widget build(BuildContext context) {
    String title = widget.taskData['title'] ?? 'Action Plan';
    List tasks = widget.taskData['tasks'] ?? [];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF282A2C), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist, color: Color(0xFFA142F4), size: 20),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const Divider(color: Colors.white10, height: 16),
          ...List.generate(tasks.length, (i) {
            return InkWell(
              onTap: () => setState(() => _checkedState[i] = !_checkedState[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(_checkedState[i] ? Icons.check_box : Icons.check_box_outline_blank, color: _checkedState[i] ? Colors.greenAccent : Colors.white38, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tasks[i].toString(),
                        style: TextStyle(color: _checkedState[i] ? Colors.white38 : Colors.white, decoration: _checkedState[i] ? TextDecoration.lineThrough : null, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ==========================================
// GENERATIVE UI WIDGET 3: DATA CHART CARD
// ==========================================
class ChartCard extends StatelessWidget {
  final dynamic chartData;
  const ChartCard({super.key, required this.chartData});

  @override
  Widget build(BuildContext context) {
    String title = chartData['title'] ?? 'Data Summary';
    List labels = chartData['labels'] ?? [];
    List values = chartData['values'] ?? [];

    double maxVal = 1;
    for (var v in values) {
      double numVal = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 1.0;
      if (numVal > maxVal) maxVal = numVal;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF282A2C), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart, color: Color(0xFF1A73E8), size: 20),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(labels.length, (i) {
            double numVal = (i < values.length && values[i] is num) ? values[i].toDouble() : double.tryParse(values[i].toString()) ?? 0.0;
            double ratio = (numVal / maxVal).clamp(0.05, 1.0);

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(labels[i].toString(), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      Text(numVal.toStringAsFixed(0), style: const TextStyle(color: Color(0xFF1A73E8), fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FractionallySizedBox(
                    widthFactor: ratio,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF1A73E8), Color(0xFFA142F4)]),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// COSMIC FLOATING PARTICLES PAINTER
class CosmicParticlePainter extends CustomPainter {
  final double animationValue;
  CosmicParticlePainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final random = math.Random(42);
    for (int i = 0; i < 40; i++) {
      double startX = random.nextDouble() * size.width;
      double startY = random.nextDouble() * size.height;
      double radius = 1.0 + random.nextDouble() * 2.5;
      double speed = 0.3 + random.nextDouble() * 0.7;

      double y = (startY - (animationValue * size.height * speed)) % size.height;
      double opacity = 0.15 + 0.5 * math.sin((animationValue * 2 + i) * math.pi);

      paint.color = Colors.white.withOpacity(opacity.clamp(0.1, 0.75));
      canvas.drawCircle(Offset(startX, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CosmicParticlePainter oldDelegate) =>
      oldDelegate.animationValue != animationValue;
}
