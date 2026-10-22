import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/media/android_chat_secure_media_service.dart';

class ChatAudioRecorder extends StatefulWidget {
  const ChatAudioRecorder({
    super.key,
    required this.onRecorded,
    required this.onDismiss,
    required this.onError,
    this.service = const AndroidChatSecureMediaService(),
  });

  /// Completes only after the encrypted send is durably accepted into the
  /// local queue. Throw on failure so the recorder remains an explicit error.
  final Future<void> Function(SecureMediaAttachment attachment) onRecorded;
  final VoidCallback onDismiss;
  final void Function(String message) onError;
  final AndroidChatSecureMediaService service;

  @override
  State<ChatAudioRecorder> createState() => _ChatAudioRecorderState();
}

class _ChatAudioRecorderState extends State<ChatAudioRecorder>
    with WidgetsBindingObserver {
  bool _recording = false;
  bool _paused = false;
  bool _busy = false;
  bool _closed = false;
  bool _polling = false;
  bool _errorReported = false;
  int _seconds = 0;
  Timer? _timer;
  Future<void>? _cancellation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_cancel());
    }
  }

  void _dismiss() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    if (mounted) widget.onDismiss();
  }

  Future<void> _failure(Object error) async {
    _timer?.cancel();
    if (mounted && !_closed) setState(() => _busy = true);
    Object? cleanupError;
    try {
      await widget.service.cancelRecording();
    } catch (error) {
      cleanupError = error;
    }
    final cleanupMessage = cleanupError == null
        ? ''
        : ' Cleanup also failed: $cleanupError';
    try {
      _reportError(
        'Recording interrupted or unavailable: $error.$cleanupMessage',
      );
    } finally {
      _dismiss();
    }
  }

  void _reportError(String message) {
    if (_errorReported) return;
    _errorReported = true;
    widget.onError(message);
  }

  Future<void> _start() async {
    if (_busy || _closed) return;
    setState(() => _busy = true);
    try {
      await widget.service.startRecording();
      if (!mounted || _closed) {
        try {
          await widget.service.cancelRecording();
        } catch (error) {
          _reportError('Could not clean up the interrupted recording: $error');
        }
        return;
      }
      setState(() => _recording = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _closed || _busy) return;
        if (!_paused) setState(() => _seconds++);
        if (_seconds >=
            AndroidChatSecureMediaService.maxRecordingDuration.inSeconds) {
          unawaited(_stop());
        } else {
          unawaited(_observeRecording());
        }
      });
    } catch (error) {
      await _failure(error);
    } finally {
      if (mounted && !_closed) setState(() => _busy = false);
    }
  }

  Future<void> _observeRecording() async {
    if (_polling || _closed || _busy) return;
    _polling = true;
    try {
      final status = await widget.service.recordingStatus();
      if (_closed || !mounted || _busy) return;
      if (status == 'completed') {
        await _stop();
      } else if (status == 'failed' || status == 'interrupted') {
        await _failure(StateError('Microphone recording was interrupted.'));
      }
    } catch (error) {
      if (!_closed && mounted) await _failure(error);
    } finally {
      _polling = false;
    }
  }

  Future<void> _togglePause() async {
    if (_busy || _closed || !_recording) return;
    setState(() => _busy = true);
    try {
      if (_paused) {
        await widget.service.resumeRecording();
      } else {
        await widget.service.pauseRecording();
      }
      if (mounted && !_closed) setState(() => _paused = !_paused);
    } catch (error) {
      await _failure(error);
    } finally {
      if (mounted && !_closed) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    if (_busy || _closed || !_recording) return;
    _timer?.cancel();
    setState(() => _busy = true);
    SecureMediaAttachment? attachment;
    try {
      attachment = await widget.service.stopRecording();
      if (!mounted || _closed) return;
      // The caller must throw if durable queue acceptance fails.
      await widget.onRecorded(attachment);
      _dismiss();
    } catch (error) {
      await _failure(error);
    } finally {
      attachment?.bytes.fillRange(0, attachment.bytes.length, 0);
      if (mounted && !_closed) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_closed) return;
    final pending = _cancellation;
    if (pending != null) return pending;
    final cancellation = _cancelAndDismiss();
    _cancellation = cancellation;
    return cancellation;
  }

  Future<void> _cancelAndDismiss() async {
    _timer?.cancel();
    if (mounted) setState(() => _busy = true);
    try {
      await widget.service.cancelRecording();
    } catch (error) {
      _reportError('Could not clean up the cancelled recording: $error');
    } finally {
      _dismiss();
    }
  }

  @override
  void dispose() {
    final wasDismissed = _closed;
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    if (!wasDismissed) unawaited(_cleanupAfterDispose());
    super.dispose();
  }

  Future<void> _cleanupAfterDispose() async {
    try {
      await widget.service.cancelRecording();
    } catch (error) {
      _reportError(
        'Could not clean up the recording after leaving chat: $error',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final elapsed =
        '${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}';
    final status = _busy
        ? 'Please wait'
        : _paused
        ? 'Paused'
        : _recording
        ? 'Recording'
        : 'Ready to record';
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * .8,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Record audio',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              Center(
                child: Semantics(
                  liveRegion: true,
                  label: '$status. Elapsed recording time $elapsed.',
                  child: Column(
                    children: [
                      ExcludeSemantics(
                        child: CircleAvatar(
                          radius: 42,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          child: Icon(
                            _paused ? Icons.pause : Icons.mic,
                            size: 42,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        elapsed,
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        status,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Maximum recording time: 5 minutes',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  if (!_recording)
                    FilledButton.icon(
                      onPressed: _busy ? null : _start,
                      icon: const Icon(Icons.mic),
                      label: const Text('Start'),
                      style: _actionStyle,
                    )
                  else ...[
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _togglePause,
                      icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                      label: Text(_paused ? 'Resume' : 'Pause'),
                      style: _actionStyle,
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _stop,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop and send'),
                      style: _actionStyle,
                    ),
                  ],
                  TextButton.icon(
                    onPressed: _busy ? null : _cancel,
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel'),
                    style: _actionStyle,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  ButtonStyle get _actionStyle =>
      const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(132, 52)));
}
