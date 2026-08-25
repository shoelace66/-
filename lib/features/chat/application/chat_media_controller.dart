import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../media/domain/services/image_cache_service.dart';
import '../../../core/utils/image_prompt_polisher.dart';
import '../../../infrastructure/services/image_generation_service.dart';
import '../../../infrastructure/services/tts_service.dart';
import '../data/models/contact.dart';
import '../data/models/message.dart';
import '../domain/providers/chat_provider.dart';

class MessageImageGenerationResult {
  const MessageImageGenerationResult._({this.error});

  const MessageImageGenerationResult.success() : this._();
  const MessageImageGenerationResult.failure(String error)
      : this._(error: error);

  final String? error;
  bool get isSuccess => error == null;
}

class ChatMediaController extends ChangeNotifier {
  ChatMediaController({
    required this.provider,
    ImageGenerationService? imageService,
    TtsService? ttsService,
  })  : _imageService = imageService ?? ImageGenerationService.instance,
        _ttsService = ttsService ?? TtsService.instance {
    _ttsService.addListener(notifyListeners);
  }

  final ChatProvider provider;
  final ImageGenerationService _imageService;
  final TtsService _ttsService;

  bool isSpeaking(Message message) => _ttsService.isPlayingMessage(message.id);

  Future<void> speak(Message message) async {
    final contact = provider.selectedContact;
    final text = message.content.trim();
    if (contact == null || text.isEmpty) return;
    if (_ttsService.isPlayingMessage(message.id)) {
      await _ttsService.stop();
      return;
    }
    if (_ttsService.state != TtsPlaybackState.idle) {
      await _ttsService.stop();
    }
    final voice = VoiceOption.findById(contact.voice) ?? VoiceOption.fallback;
    await _ttsService.speak(
      messageId: message.id,
      text: text,
      voice: voice,
    );
  }

  Future<void> stopSpeaking() => _ttsService.stop();

  Future<MessageImageGenerationResult> generateImage({
    required String contactId,
    required String userPrompt,
  }) async {
    PolishedImagePrompt polished;
    try {
      polished = await provider.polishImagePrompt(
        userDescription: userPrompt,
        contactId: contactId,
      );
    } catch (_) {
      polished = PolishedImagePrompt(
        englishPrompt: userPrompt,
        negativePrompt: '',
      );
    }

    final generated = await _imageService.generate(
      prompt: polished.englishPrompt,
    );
    if (!generated.success) {
      return MessageImageGenerationResult.failure(
        generated.error ?? '未知错误',
      );
    }
    await provider.appendImageMessage(
      contactId: contactId,
      prompt: polished.englishPrompt,
      originalPrompt: userPrompt,
      imageUrl: generated.imageUrl,
    );
    if (generated.imageUrl != null) {
      unawaited(ImageCacheService.instance.cacheImage(
        url: generated.imageUrl!,
        contactId: contactId,
        prompt: polished.englishPrompt,
      ));
    }
    await _ttsService.stop();
    return const MessageImageGenerationResult.success();
  }

  @override
  void dispose() {
    _ttsService.removeListener(notifyListeners);
    super.dispose();
  }
}
