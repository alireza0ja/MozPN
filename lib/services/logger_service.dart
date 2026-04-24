import 'package:flutter/foundation.dart';

class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;
  LoggerService._internal();

  final List<LogEntry> _logs = [];
  final int _maxLogs = 100;

  ValueNotifier<List<LogEntry>> logsNotifier = ValueNotifier([]);

  void log(String message, {LogType type = LogType.info}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      message: message,
      type: type,
    );
    _logs.insert(0, entry);
    if (_logs.length > _maxLogs) {
      _logs.removeLast();
    }
    logsNotifier.value = List.from(_logs);
    if (kDebugMode) {
      print('[${type.name.toUpperCase()}] $message');
    }
  }

  void clear() {
    _logs.clear();
    logsNotifier.value = [];
  }

  String getAllLogsText() {
    return _logs.reversed
        .map((e) => "[${e.timestamp.toIso8601String()}] [${e.type.name.toUpperCase()}] ${e.message}")
        .join("\n");
  }
}

enum LogType { info, warning, error, success }

class LogEntry {
  final DateTime timestamp;
  final String message;
  final LogType type;

  LogEntry({
    required this.timestamp,
    required this.message,
    required this.type,
  });
}
