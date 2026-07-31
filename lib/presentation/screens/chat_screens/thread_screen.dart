import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/entities/chat_message.dart';
import '../../../domain/entities/chat_thread.dart';
import '../../../domain/entities/chat_user.dart';
import '../../state/chat/active_thread_cubit.dart';
import '../../widgets/chat/message_bubble.dart';

/// The 1:1 chat thread screen.
class ThreadScreen extends StatefulWidget {
  const ThreadScreen({
    super.key,
    required this.thread,
    required this.otherUser,
  });

  final ChatThread thread;
  final ChatUser otherUser;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker = ImagePicker();
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    context.read<ActiveThreadCubit>().openThread(
          thread: widget.thread,
          otherUser: widget.otherUser,
        );
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      context.read<ActiveThreadCubit>().loadOlderMessages();
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildTypingBanner(),
          _buildInputBar(context),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      leadingWidth: 40,
      title: BlocBuilder<ActiveThreadCubit, ActiveThreadState>(
        builder: (context, state) {
          final online = state is ActiveThreadLoaded
              ? state.otherUser.isOnline
              : widget.otherUser.isOnline;
          return Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: widget.otherUser.photoUrl != null
                    ? NetworkImage(widget.otherUser.photoUrl!)
                    : null,
                child: widget.otherUser.photoUrl == null
                    ? Text(widget.otherUser.initials)
                    : null,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.otherUser.displayName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(
                    online ? 'Online' : 'Offline',
                    style: TextStyle(
                      fontSize: 12,
                      color: online ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMessageList() {
    return BlocBuilder<ActiveThreadCubit, ActiveThreadState>(
      builder: (context, state) {
        if (state is ActiveThreadLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is ActiveThreadError) {
          return Center(child: Text(state.message));
        }
        if (state is ActiveThreadLoaded) {
          final msgs = state.messages;
          if (msgs.isEmpty) {
            return const Center(
              child: Text('No messages yet. Say hello! 👋'),
            );
          }
          return ListView.builder(
            controller: _scrollCtrl,
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: msgs.length + (state.hasMore ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == msgs.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              final msg = msgs[i];
              final isMine = msg.senderId ==
                  context.read<ActiveThreadCubit>().myUid;
              return MessageBubble(
                message: msg,
                isMine: isMine,
                onDeleteForMe: () => context
                    .read<ActiveThreadCubit>()
                    .deleteMessageForMe(msg),
                onDeleteForEveryone: isMine
                    ? () => context
                        .read<ActiveThreadCubit>()
                        .deleteMessageForEveryone(msg)
                    : null,
              );
            },
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildTypingBanner() {
    return BlocBuilder<ActiveThreadCubit, ActiveThreadState>(
      buildWhen: (prev, next) {
        final prevTyping =
            prev is ActiveThreadLoaded ? prev.otherIsTyping : false;
        final nextTyping =
            next is ActiveThreadLoaded ? next.otherIsTyping : false;
        return prevTyping != nextTyping;
      },
      builder: (context, state) {
        final typing =
            state is ActiveThreadLoaded ? state.otherIsTyping : false;
        if (!typing) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 4),
          child: Row(
            children: [
              Text(
                '${widget.otherUser.displayName} is typing...',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputBar(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file),
              onPressed: () => _pickMedia(context),
            ),
            Expanded(
              child: TextField(
                controller: _textCtrl,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: 'Message',
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onChanged: (v) =>
                    context.read<ActiveThreadCubit>().onTextChanged(v),
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton.small(
              heroTag: 'send_btn',
              onPressed: () {
                final text = _textCtrl.text;
                if (text.trim().isEmpty) return;
                _textCtrl.clear();
                context.read<ActiveThreadCubit>().sendText(text);
              },
              child: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickMedia(BuildContext context) async {
    // Capture before any await to satisfy use_build_context_synchronously.
    final cubit = context.read<ActiveThreadCubit>();
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo from gallery'),
              onTap: () => Navigator.pop(context, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Video from gallery'),
              onTap: () => Navigator.pop(context, 'video'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    XFile? file;
    MessageType? type;

    if (choice == 'photo') {
      file = await _picker.pickImage(source: ImageSource.gallery);
      type = MessageType.image;
    } else if (choice == 'camera') {
      file = await _picker.pickImage(source: ImageSource.camera);
      type = MessageType.image;
    } else if (choice == 'video') {
      file = await _picker.pickVideo(source: ImageSource.gallery);
      type = MessageType.video;
    }

    if (file == null || type == null || !mounted) return;

    final bytes = await file.readAsBytes();
    final msgId = _uuid.v4();
    if (!mounted) return;
    await cubit.sendMedia(
          messageId: msgId,
          rawBytes: bytes,
          type: type,
        );
  }
}
