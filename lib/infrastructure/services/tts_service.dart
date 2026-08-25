import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

import 'package:flutter/foundation.dart';

import '../../core/data/models/provider_settings.dart';
import '../../features/chat/data/models/contact.dart';

enum TtsPlaybackState { idle, loading, playing }

abstract interface class TtsAudioPlayback {
  Stream<void> get onComplete;

  Future<void> play(Uint8List bytes);

  Future<void> stop();
}

final class AudioplayersTtsAudioPlayback implements TtsAudioPlayback {
  final AudioPlayer _player = AudioPlayer();

  @override
  Stream<void> get onComplete => _player.onPlayerComplete;

  @override
  Future<void> play(Uint8List bytes) {
    return _player.play(
      BytesSource(bytes),
      mode: PlayerMode.mediaPlayer,
    );
  }

  @override
  Future<void> stop() => _player.stop();
}

class TtsServiceException implements Exception {
  const TtsServiceException(this.userMessage, {this.cause});

  final String userMessage;
  final Object? cause;

  @override
  String toString() => userMessage;
}

class TtsService extends ChangeNotifier {
  TtsService._internal();

  static final TtsService instance = TtsService._internal();

  TtsPlaybackState _state = TtsPlaybackState.idle;
  String? _currentMessageId;
  String? _currentVoiceId;

  TtsProfile _profile = const TtsProfile();

  /// 测试 / 高级用途：注入自定义 http.Client
  http.Client? _clientOverride;
  http.Client? _sharedClient;
  TtsAudioPlayback? _audioPlaybackOverride;
  TtsAudioPlayback? _defaultAudioPlayback;
  StreamSubscription<void>? _playbackCompleteSubscription;

  TtsPlaybackState get state => _state;
  String? get currentMessageId => _currentMessageId;
  String? get currentVoiceId => _currentVoiceId;
  TtsProfile get profile => _profile;

  bool isPlayingMessage(String messageId) =>
      _state == TtsPlaybackState.playing && _currentMessageId == messageId;

  void updateProfile(TtsProfile profile) {
    _profile = profile;
  }

  /// 给测试 / 高级场景用：注入自定义 client。
  // ignore: use_setters_to_change_properties
  void debugSetHttpClient(http.Client? client) {
    _clientOverride = client;
  }

  /// 给测试 / 高级场景用：注入音频播放实现。
  // ignore: use_setters_to_change_properties
  void debugSetAudioPlayback(TtsAudioPlayback? playback) {
    _audioPlaybackOverride = playback;
  }

  http.Client get _http => _clientOverride ?? (_sharedClient ??= http.Client());
  TtsAudioPlayback get _audioPlayback =>
      _audioPlaybackOverride ??
      (_defaultAudioPlayback ??= AudioplayersTtsAudioPlayback());

  /// 合成并播放文本
  ///
  /// [profile] 可选：传了就用，没传就用 [updateProfile] 注入的最新值。
  /// [voice] 来自 [VoiceOption]，允许覆盖 profile.model（联系人级音色优先）。
  ///
  /// [_fetchAudio] 调 HTTP 服务拿到 mp3/wav bytes，再交给系统媒体播放器；
  /// 播放完成或用户主动停止时会恢复为 idle 状态。
  Future<void> speak({
    required String messageId,
    required String text,
    required VoiceOption voice,
    TtsProfile? profile,
  }) async {
    if (text.trim().isEmpty) return;

    if (_state == TtsPlaybackState.playing && _currentMessageId == messageId) {
      return;
    }
    if (_state != TtsPlaybackState.idle) {
      await stop();
    }

    final effective = profile ?? _profile;
    final voiceId = voice.id;

    _setState(TtsPlaybackState.loading, messageId, voiceId);

    try {
      final bytes = await _fetchAudio(
        text: text,
        voiceId: voiceId,
        profile: effective,
      );
      if (_currentMessageId != messageId) {
        // 用户在加载阶段点了 stop
        return;
      }
      if (bytes == null || bytes.isEmpty) {
        debugPrint('[TtsService] 收到空音频，跳过播放');
        if (_currentMessageId == messageId) {
          _reset();
        }
        return;
      }
      await _playbackCompleteSubscription?.cancel();
      _playbackCompleteSubscription = _audioPlayback.onComplete.listen(
        (_) => _handlePlaybackComplete(messageId),
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('[TtsService] 播放失败: $error');
          _handlePlaybackComplete(messageId);
        },
      );
      _setState(TtsPlaybackState.playing, messageId, voiceId);
      await _audioPlayback.play(bytes);
    } on TtsServiceException catch (e) {
      debugPrint('[TtsService] ${e.userMessage}');
      if (_currentMessageId == messageId) {
        _reset();
      }
    } catch (e) {
      debugPrint('[TtsService] 未知错误: $e');
      if (_currentMessageId == messageId) {
        _reset();
      }
    }
  }

  /// 停止当前播放
  Future<void> stop() async {
    if (_state == TtsPlaybackState.idle) return;
    debugPrint('[TtsService] stop messageId=$_currentMessageId');
    await _playbackCompleteSubscription?.cancel();
    _playbackCompleteSubscription = null;
    if (_state == TtsPlaybackState.playing) {
      try {
        await _audioPlayback.stop();
      } catch (error) {
        debugPrint('[TtsService] 停止播放失败: $error');
      }
    }
    _reset();
  }

  void _handlePlaybackComplete(String messageId) {
    if (_currentMessageId != messageId) return;
    final subscription = _playbackCompleteSubscription;
    _playbackCompleteSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    _reset();
  }

  // ---- 真实 HTTP 拉取 ----

  Future<Uint8List?> _fetchAudio({
    required String text,
    required String voiceId,
    required TtsProfile profile,
  }) async {
    final presetId = profile.presetId;
    switch (presetId) {
      case 'openai_tts':
        return _fetchOpenAiTts(
          text: text,
          voiceId: voiceId,
          profile: profile,
        );
      case 'edge_tts':
        return _fetchEdgeTts(
          text: text,
          voiceId: voiceId,
          profile: profile,
        );
      case 'custom_tts':
      default:
        return _fetchCustomTts(
          text: text,
          voiceId: voiceId,
          profile: profile,
        );
    }
  }

  Future<Uint8List> _fetchOpenAiTts({
    required String text,
    required String voiceId,
    required TtsProfile profile,
  }) async {
    if (profile.apiKey.trim().isEmpty) {
      throw const TtsServiceException('OpenAI TTS 需要 API Key');
    }
    if (profile.baseUrl.trim().isEmpty) {
      throw const TtsServiceException('请先填写 OpenAI TTS 的 Base URL');
    }
    final url = '${profile.baseUrl}/audio/speech';
    final model = profile.model.isEmpty ? 'tts-1' : profile.model;
    final payload = <String, dynamic>{
      'model': model,
      'input': text,
      'voice': _openAiVoiceId(voiceId),
      'response_format': 'mp3',
    };
    final response = await _http
        .post(
          Uri.parse(url),
          headers: <String, String>{
            'Authorization': 'Bearer ${profile.apiKey.trim()}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(Duration(seconds: profile.timeoutSeconds));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TtsServiceException(_mapHttpStatus(response.statusCode));
    }
    if (response.bodyBytes.isEmpty) {
      throw const TtsServiceException('OpenAI TTS 返回空内容');
    }
    return response.bodyBytes;
  }

  Future<Uint8List?> _fetchEdgeTts({
    required String text,
    required String voiceId,
    required TtsProfile profile,
  }) async {
    if (profile.baseUrl.trim().isEmpty) {
      throw const TtsServiceException(
          'Edge TTS 需要中转 / 本地代理服务，请先在"API 提供商 → TTS"中填写 Base URL');
    }
    final url = '${profile.baseUrl}/tts';
    final response = await _http
        .post(
          Uri.parse(url),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, dynamic>{
            'text': text,
            'voice': voiceId,
          }),
        )
        .timeout(Duration(seconds: profile.timeoutSeconds));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TtsServiceException(_mapHttpStatus(response.statusCode));
    }
    if (response.bodyBytes.isEmpty) return null;
    return response.bodyBytes;
  }

  Future<Uint8List?> _fetchCustomTts({
    required String text,
    required String voiceId,
    required TtsProfile profile,
  }) async {
    if (profile.baseUrl.trim().isEmpty) {
      throw const TtsServiceException('自定义 TTS 需要先填写 Base URL');
    }
    final response = await _http
        .post(
          Uri.parse(profile.baseUrl),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, dynamic>{
            'text': text,
            'voice': voiceId,
            'model': profile.model,
          }),
        )
        .timeout(Duration(seconds: profile.timeoutSeconds));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TtsServiceException(_mapHttpStatus(response.statusCode));
    }
    if (response.bodyBytes.isEmpty) return null;
    return response.bodyBytes;
  }

  /// Edge-TTS 音色 ID → OpenAI 合法 voice 名称
  String _openAiVoiceId(String raw) {
    if (raw.isEmpty) return 'alloy';
    if (raw == 'zh-CN-XiaoxiaoNeural' ||
        raw == 'zh-CN-XiaoyiNeural' ||
        raw == 'zh-CN-XiaobeiNeural' ||
        raw == 'zh-CN-XiaoniNeural') {
      return 'shimmer';
    }
    if (raw == 'zh-CN-YunxiNeural' ||
        raw == 'zh-CN-YunyangNeural' ||
        raw == 'zh-CN-YunjianNeural') {
      return 'onyx';
    }
    if (raw == 'en-US-JennyNeural') return 'nova';
    if (raw == 'en-US-GuyNeural') return 'echo';
    if (raw == 'ja-JP-NanamiNeural') return 'alloy';
    return raw;
  }

  String _mapHttpStatus(int status) {
    if (status == 401 || status == 403) {
      return 'TTS：API Key 无效或无权限（HTTP $status）';
    }
    if (status == 404) {
      return 'TTS：路径不存在（HTTP 404）— 检查 baseUrl / model';
    }
    if (status == 429) {
      return 'TTS：请求过于频繁或额度不足（HTTP 429）';
    }
    if (status >= 500) {
      return 'TTS：服务暂时不可用（HTTP $status）';
    }
    return 'TTS：HTTP $status';
  }

  void _setState(TtsPlaybackState state, String? messageId, String? voiceId) {
    _state = state;
    _currentMessageId = messageId;
    _currentVoiceId = voiceId;
    notifyListeners();
  }

  void _reset() {
    _state = TtsPlaybackState.idle;
    _currentMessageId = null;
    _currentVoiceId = null;
    notifyListeners();
  }
}
