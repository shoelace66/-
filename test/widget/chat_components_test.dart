import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_chat_demo/features/chat/data/models/message.dart';
import 'package:flutter_chat_demo/core/data/models/provider_settings.dart';
import 'package:flutter_chat_demo/features/chat/presentation/widgets/chat_actions.dart';
import 'package:flutter_chat_demo/features/chat/presentation/widgets/chat_message_list.dart';
import 'package:flutter_chat_demo/features/chat/presentation/widgets/chat_status_views.dart';
import 'package:flutter_chat_demo/features/chat/presentation/widgets/message_composer.dart';

void main() {
  testWidgets('消息输入框按状态切换发送和停止动作', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var sends = 0;
    var cancels = 0;

    Future<void> pump({required bool generating}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageComposer(
              controller: controller,
              enabled: true,
              isGenerating: generating,
              canCancel: true,
              onSend: () => sends++,
              onCancel: () => cancels++,
            ),
          ),
        ),
      );
    }

    await pump(generating: false);
    await tester.tap(find.byKey(const ValueKey('message-composer-action')));
    expect(sends, 1);
    expect(find.text('发送'), findsOneWidget);

    await pump(generating: true);
    await tester.tap(find.byKey(const ValueKey('message-composer-action')));
    expect(cancels, 1);
    expect(find.text('停止'), findsOneWidget);
  });

  testWidgets('消息列表渲染分页入口、稳定 key 与输入指示', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final message = Message(
      id: 'assistant-1',
      role: MessageRole.assistant,
      content: '测试回复',
      createdAt: DateTime(2026),
    );
    var olderLoads = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageList(
            messages: [message],
            controller: controller,
            isTyping: true,
            hasOlderMessages: true,
            isLoadingOlderMessages: false,
            totalMessageCount: 101,
            canRegenerateLastTurn: true,
            onLoadOlder: () => olderLoads++,
            onRetry: (_) {},
            onGenerateImage: (_) {},
            onRegenerate: () {},
            canCreateBranch: (_) => false,
            onCreateBranch: (_) {},
            onSpeak: (_) {},
            onStopSpeak: () {},
            isSpeaking: (_) => false,
            onEdit: (_) {},
            onDelete: (_) {},
            onQuote: (_) {},
            onGenerateCandidate: (_) {},
            onShowCandidates: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('测试回复'), findsOneWidget);
    expect(find.byKey(const ValueKey('assistant-1-text')), findsOneWidget);
    expect(find.byKey(const ValueKey('typing-bubble')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('load-older-messages')));
    expect(olderLoads, 1);
  });

  testWidgets('空态和错误态提供可访问语义', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(child: ChatEmptyState(hasContact: false)),
              ChatErrorBanner(message: '本地数据库不可用'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('暂无对象，请先创建'), findsOneWidget);
    expect(find.text('本地数据库不可用'), findsOneWidget);
    final node = tester.getSemantics(
      find.byKey(const ValueKey('chat-error-semantics')),
    );
    expect(node.label, contains('错误：本地数据库不可用'));
    semantics.dispose();
  });

  testWidgets('紧凑动作区复用同一组聊天操作', (tester) async {
    var created = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatActions(
            compact: true,
            hasContact: false,
            canRecall: false,
            debugMode: false,
            onCreateContact: () => created++,
            onRecall: () {},
            onProviders: () {},
            onMemory: () {},
            onTimeline: () {},
            onSearch: () {},
            onWorldBook: () {},
            onImageGallery: () {},
            onBackup: () {},
            onSystemPrompt: () {},
            onSettings: () {},
            onAssistantSettings: () {},
            onToggleDebug: () {},
            profiles: const [LlmProfile()],
            activeProfile: const LlmProfile(),
            onActivateProfile: (_) {},
            onCheckProfiles: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('聊天操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建对象'));
    expect(created, 1);
  });
}
