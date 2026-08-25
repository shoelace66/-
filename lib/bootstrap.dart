import 'package:flutter/material.dart';

import 'app.dart';
import 'features/chat/application/chat_view_state.dart';
import 'features/chat/domain/providers/chat_provider.dart';

class AppBootstrapResult {
  const AppBootstrapResult({required this.chatProvider});

  final ChatProvider chatProvider;
}

Future<AppBootstrapResult> bootstrap() async {
  final chatProvider = ChatProvider();
  try {
    await chatProvider.initialize();
    return AppBootstrapResult(chatProvider: chatProvider);
  } catch (_) {
    chatProvider.dispose();
    rethrow;
  }
}

typedef AppBootstrapper = Future<AppBootstrapResult> Function();

class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key, this.bootstrapper = bootstrap});

  final AppBootstrapper bootstrapper;

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  late Future<AppBootstrapResult> _future;
  AppBootstrapResult? _result;

  @override
  void initState() {
    super.initState();
    _future = _start();
  }

  Future<AppBootstrapResult> _start() async {
    final result = await widget.bootstrapper();
    _result = result;
    return result;
  }

  void _retry() {
    _result?.chatProvider.dispose();
    _result = null;
    _future = _start();
    setState(() {});
  }

  @override
  void dispose() {
    _result?.chatProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppBootstrapResult>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return ChatApp(chatProvider: snapshot.requireData.chatProvider);
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: snapshot.hasError
                ? _BootstrapFailureView(error: snapshot.error!, onRetry: _retry)
                : const _BootstrapLoadingView(),
          ),
        );
      },
    );
  }
}

class _BootstrapLoadingView extends StatelessWidget {
  const _BootstrapLoadingView();

  @override
  Widget build(BuildContext context) => Center(
        child: Semantics(
          liveRegion: true,
          label: '正在初始化应用',
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在初始化本地数据…'),
            ],
          ),
        ),
      );
}

class _BootstrapFailureView extends StatelessWidget {
  const _BootstrapFailureView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failure = error is ChatInitializationFailure
        ? error as ChatInitializationFailure
        : ChatInitializationFailure('应用', error);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text('${failure.module}初始化失败'),
            const SizedBox(height: 8),
            Text(
              failure.cause.toString(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey('bootstrap-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
