import 'package:flutter/material.dart';

import '../../domain/entities/chat_message.dart';

class DataSmsMeta extends StatelessWidget {
  const DataSmsMeta({
    super.key,
    required this.message,
    required this.isMine,
    required this.color,
  });

  final ChatMessage message;
  final bool isMine;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final state = switch (message.smsDeliveryState) {
      'delivered' => 'Device delivered',
      'sent' => 'Sent; delivery unconfirmed',
      'failed' => 'Not sent',
      'partial' => 'Partially sent',
      'unconfirmed' => 'Delivery unconfirmed',
      _ => 'Sending',
    };
    final segments = message.smsSegments ?? 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Data SMS · $segments ${segments == 1 ? 'segment' : 'segments'}',
          style: TextStyle(fontSize: 11, color: color),
        ),
        if (isMine) Text(state, style: TextStyle(fontSize: 11, color: color)),
        if (isMine && message.smsError?.isNotEmpty == true)
          Text(
            message.smsError!,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
      ],
    );
  }
}
