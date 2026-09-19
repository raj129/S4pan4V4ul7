import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/widgets/app_surfaces.dart';
import '../../state/chat/user_lookup_cubit.dart';
import '../../theme/app_spacing.dart';
import 'thread_screen.dart';

/// Screen for starting a chat by entering an email only.
class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Chat'),
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: BlocListener<UserLookupCubit, UserLookupState>(
        listener: (context, state) {
          if (state is UserLookupFound) {
            openThreadScreen(
              context,
              thread: state.thread,
              otherUser: state.user,
              replace: true,
            );
          } else if (state is UserLookupError) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.huge,
          ),
          children: [
            _buildEmailForm(context),
            const SizedBox(height: AppSpacing.lg),
            const InfoBanner(
              tone: InfoBannerTone.info,
              icon: Icons.privacy_tip_outlined,
              title: 'Private start',
              message:
                  'Chats begin by email only. The app does not reveal who is '
                  'already on the platform before you try.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailForm(BuildContext context) {
    return BlocBuilder<UserLookupCubit, UserLookupState>(
      builder: (context, state) {
        return Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(
                'Start by email',
                padding: EdgeInsets.only(bottom: AppSpacing.sm),
              ),
              TextFormField(
                controller: _controller,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  hintText: 'user@gmail.com',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Please enter an email address.';
                  }
                  final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                  if (!emailRegex.hasMatch(v.trim())) {
                    return 'Enter a valid email address.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                icon: state is UserLookupLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_search_rounded),
                label: Text(
                  state is UserLookupLoading ? 'Searching…' : 'Start chat',
                ),
                onPressed: state is UserLookupLoading
                    ? null
                    : () {
                        if (_formKey.currentState?.validate() ?? false) {
                          context.read<UserLookupCubit>().lookupByEmail(
                            _controller.text.trim(),
                          );
                        }
                      },
              ),
              if (state is UserLookupNotFound) ...[
                const SizedBox(height: AppSpacing.md),
                InfoBanner(
                  tone: InfoBannerTone.error,
                  icon: Icons.person_off_outlined,
                  message: '${state.email} is not registered.',
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
