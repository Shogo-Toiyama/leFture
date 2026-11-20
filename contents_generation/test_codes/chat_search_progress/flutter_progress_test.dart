import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/chat/chat_conversation.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/chat/chat_repository.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:lefture/infrastructure/local_db/repositories/chat_cache_drift.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_labels.dart';

import '../../../user_interface/test/application/chat/fake_chat_repository.dart';

void main() {
  for (final locale in [const Locale('en'), const Locale('ja')]) {
    test(
      'Streaming status uses the current search target in ${locale.languageCode}',
      () async {
        final repo = FakeChatRepository();
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final container = ProviderContainer(
          overrides: [
            chatRepositoryProvider.overrideWithValue(repo),
            chatCacheDriftProvider.overrideWithValue(ChatCacheDrift(db)),
          ],
        );
        final chat = container.read(chatConversationProvider.notifier);
        final l10n = await AppLocalizations.delegate.load(locale);

        Future<void> check(ChatStatusEvent event, String expected) async {
          repo.controller.add(event);
          await Future<void>.delayed(Duration.zero);
          final reply = container.read(chatConversationProvider).messages.last;
          expect(chatStageLabel(l10n, reply), expected);
          expect(reply.searchTarget, event.target);
          expect(reply.searchQuery, event.query);
        }

        final sent = chat.send('Find related information.');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        repo.controller.add(
          const ChatMetaEvent(
            threadId: 'T1',
            userMessageId: 'U1',
            assistantMessageId: 'A1',
          ),
        );
        try {
          await check(
            const ChatStatusEvent(stage: ChatStage.searching),
            l10n.aiChatStageThinking,
          );
          await check(
            const ChatStatusEvent(
              stage: ChatStage.searching,
              detail: ['web'],
              target: 'web',
              query: 'electric ferries',
            ),
            l10n.aiChatStageSearchingWebWithQuery('electric ferries'),
          );
          await check(
            const ChatStatusEvent(
              stage: ChatStage.searching,
              detail: ['web'],
              target: 'web',
              handle: 'W1',
            ),
            l10n.aiChatStageSearchingWeb,
          );
          await check(
            const ChatStatusEvent(
              stage: ChatStage.searching,
              detail: ['lectures'],
            ),
            l10n.aiChatStageSearching,
          );
          await check(
            const ChatStatusEvent(
              stage: ChatStage.searching,
              detail: ['chats'],
            ),
            l10n.aiChatStageSearchingChats,
          );
          await check(
            const ChatStatusEvent(
              stage: ChatStage.searching,
              detail: ['organizing'],
            ),
            l10n.aiChatStageOrganizingMaterials,
          );
        } finally {
          repo.controller.add(
            const ChatDoneEvent(
              status: ChatMessageStatus.complete,
              creditsCharged: 0,
            ),
          );
          await repo.controller.close();
          await sent;
          await chat.settle();
          container.dispose();
          await db.close();
        }
      },
    );
  }
}
