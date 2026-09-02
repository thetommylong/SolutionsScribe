import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';

/// One-time confirmation shown the first time the user changes the Whisper
/// model. Accepting writes a persistent 0-byte marker so they're never asked
/// again; dismissing leaves the model unchanged.
class ModelAckDialog extends ConsumerStatefulWidget {
  final String modelName;

  const ModelAckDialog({super.key, required this.modelName});

  @override
  ConsumerState<ModelAckDialog> createState() => _ModelAckDialogState();
}

class _ModelAckDialogState extends ConsumerState<ModelAckDialog> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: mochaSurface0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Switching Whisper models',
        style: TextStyle(color: mochaText, fontSize: 18),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You\'re switching the transcription model to '
              '"${widget.modelName}". Different models trade speed, accuracy '
              'and behaviour in different ways, and not all of them will '
              'produce clean transcripts on every recording.',
              style: const TextStyle(color: mochaSubtext0, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () => setState(() => _checked = !_checked),
              child: Row(
                children: [
                  Checkbox(
                    value: _checked,
                    onChanged: (v) => setState(() => _checked = v ?? false),
                    activeColor: mochaMauve,
                    checkColor: mochaBase,
                  ),
                  const Expanded(
                    child: Text(
                      'I have read the model documentation, know what I\'m '
                      'doing, and promise not to complain to the developer if '
                      'the output turns into gibberish.',
                      style: TextStyle(color: mochaText, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: mochaSubtext0),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _checked
              ? () async {
                  final navigator = Navigator.of(context);
                  await ref
                      .read(settingsStoreProvider)
                      .markModelAcknowledged();
                  ref.invalidate(modelAcknowledgedProvider);
                  navigator.pop(true);
                }
              : null,
          style: TextButton.styleFrom(foregroundColor: mochaMauve),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

/// Tries to change the selected model, showing the one-time acknowledgement
/// dialog on first change. Returns true if the model was applied.
Future<bool> requestModelChange(
  WidgetRef ref,
  BuildContext context,
  String modelName,
) async {
  final acked = await ref.read(modelAcknowledgedProvider.future);
  if (!context.mounted) return false;
  if (!acked) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ModelAckDialog(modelName: modelName),
    );
    if (!context.mounted) return false;
    if (ok != true) return false;
  }
  ref.read(selectedModelProvider.notifier).state = modelName;
  return true;
}
