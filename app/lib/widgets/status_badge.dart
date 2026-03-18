import 'package:flutter/material.dart';

import '../models/session.dart';

class StatusBadge extends StatelessWidget {
  final SessionStatus status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      SessionStatus.starting => (Colors.amber, Icons.hourglass_top),
      SessionStatus.ready => (Colors.green, Icons.check_circle),
      SessionStatus.active => (Colors.blue, Icons.play_circle),
      SessionStatus.finished => (Colors.grey, Icons.stop_circle),
      SessionStatus.crashed => (Colors.red, Icons.error),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
