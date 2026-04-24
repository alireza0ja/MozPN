import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/logger_service.dart';

class LogViewer extends StatelessWidget {
  const LogViewer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'گزارش عملیات (Logs)',
                style: TextStyle(color: Color(0xFFFFD300), fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, color: Colors.white54, size: 20),
                    onPressed: () {
                      final text = LoggerService().getAllLogsText();
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('گزارش‌ها کپی شد'), duration: Duration(seconds: 1)),
                      );
                    },
                    tooltip: 'کپی همه گزارش‌ها',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white54),
                    onPressed: () => LoggerService().clear(),
                  ),
                ],
              ),
            ],
          ),
          const Divider(color: Colors.white12),
          Expanded(
            child: ValueListenableBuilder<List<LogEntry>>(
              valueListenable: LoggerService().logsNotifier,
              builder: (context, logs, child) {
                if (logs.isEmpty) {
                  return const Center(
                    child: Text('گزارشی موجود نیست', style: TextStyle(color: Colors.white24)),
                  );
                }
                return ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${log.timestamp.hour}:${log.timestamp.minute}:${log.timestamp.second}',
                            style: const TextStyle(color: Colors.white24, fontSize: 10, fontFamily: 'monospace'),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              log.message,
                              style: TextStyle(
                                color: _getLogColor(log.type),
                                fontSize: 12,
                              ),
                            ),
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
  }

  Color _getLogColor(LogType type) {
    switch (type) {
      case LogType.info: return Colors.white70;
      case LogType.warning: return Colors.orangeAccent;
      case LogType.error: return Colors.redAccent;
      case LogType.success: return Colors.greenAccent;
    }
  }
}
