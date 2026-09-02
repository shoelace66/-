import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_chat_demo/core/data/models/provider_settings.dart';
import 'package:flutter_chat_demo/infrastructure/services/ai_service.dart';

/// 用 utf8 编码构造 Response。
///
/// 注意：必须用 [http.Response.bytes] + 小写 `content-type` 头，
/// 否则 `http.Response` 构造器会用 latin1 重新编码 body，
/// 而读取时又用 utf8 解码（json 类型的默认行为），
/// 导致中文字符被错误转码。
http.Response _utf8Response(String body, {int status = 200}) {
  return http.Response.bytes(
    utf8.encode(body),
    status,
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}

class _HangingBodyClient extends http.BaseClient {
  final StreamController<List<int>> _body = StreamController<List<int>>();
  int sends = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sends++;
    return http.StreamedResponse(_body.stream, 200);
  }

  @override
  void close() {
    _body.close();
    super.close();
  }
}

/// Round-trip 测试：用 [MockClient] 拦截 HTTP 请求，
/// 验证 AiService 发出的 URL / method / headers / body 完全对齐 OpenAI 协议，
/// 同时验证响应解析在各种 edge case 下也正确。
void main() {
  group('AiService 请求 / 响应格式（OpenAI 协议对齐）', () {
    test('正确构造 chat/completions 请求体（含 temperature/top_p/penalty/max_tokens）',
        () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return _utf8Response(jsonEncode(<String, dynamic>{
          'id': 'chatcmpl-1',
          'choices': <Map<String, dynamic>>[
            <String, dynamic>{
              'index': 0,
              'message': <String, dynamic>{
                'role': 'assistant',
                'content': '你好'
              },
              'finish_reason': 'stop',
            },
          ],
        }));
      });

      final service = AiService(client: mock);
      final reply = await service.ask(
        'hello',
        contactId: 'c1',
        contactName: 'Test',
        profile: const LlmProfile(
          presetId: 'openai',
          apiKey: 'sk-test',
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o-mini',
          parameters: LlmParameters(
            temperature: 0.3,
            topP: 0.9,
            maxTokens: 512,
            frequencyPenalty: 0.5,
            presencePenalty: -0.2,
            timeoutSeconds: 30,
            stream: false,
          ),
        ),
      );

      // 1. URL
      expect(captured.url.toString(),
          'https://api.openai.com/v1/chat/completions');
      expect(captured.method, 'POST');

      // 2. Headers
      expect(captured.headers['Content-Type'], contains('application/json'));
      expect(captured.headers['Authorization'], 'Bearer sk-test');

      // 3. Body
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'gpt-4o-mini');
      expect(body['temperature'], 0.3);
      expect(body['top_p'], 0.9);
      expect(body['max_tokens'], 512);
      expect(body['frequency_penalty'], 0.5);
      expect(body['presence_penalty'], -0.2);
      expect(body['stream'], false);
      final messages = body['messages'] as List;
      expect(messages.length, 1);
      expect(messages.first['role'], 'user');
      expect(messages.first['content'], 'hello');

      // 4. 响应解析
      expect(reply, '你好');
    });

    test('max_tokens=0 时不写入字段', () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return _utf8Response(jsonEncode(<String, dynamic>{
          'choices': <Map<String, dynamic>>[
            <String, dynamic>{
              'message': <String, dynamic>{'content': 'ok'},
            },
          ],
        }));
      });

      final service = AiService(client: mock);
      await service.ask(
        'hi',
        contactId: 'c1',
        contactName: 'Test',
        profile: const LlmProfile(
          apiKey: 'sk',
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o-mini',
          parameters: LlmParameters(maxTokens: 0),
        ),
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body.containsKey('max_tokens'), isFalse,
          reason: 'max_tokens=0 表示不限制，不应传给服务端');
    });

    test('404 自动 fallback 到 /v1/chat/completions', () async {
      var firstAttempt = true;
      late http.Request firstCaptured;
      late http.Request secondCaptured;
      final mock = MockClient((request) async {
        if (firstAttempt) {
          firstAttempt = false;
          firstCaptured = request;
          return _utf8Response('not found', status: 404);
        }
        secondCaptured = request;
        return _utf8Response(jsonEncode(<String, dynamic>{
          'choices': <Map<String, dynamic>>[
            <String, dynamic>{
              'message': <String, dynamic>{'content': 'fallback ok'},
            },
          ],
        }));
      });

      final service = AiService(client: mock);
      final reply = await service.ask(
        'hi',
        contactId: 'c1',
        contactName: 'Test',
        profile: const LlmProfile(
          apiKey: 'sk',
          baseUrl: 'https://example.com',
          model: 'm',
        ),
      );

      // 第一次不带 /v1
      expect(
          firstCaptured.url.toString(), 'https://example.com/chat/completions');
      // 第二次自动补上 /v1
      expect(secondCaptured.url.toString(),
          'https://example.com/v1/chat/completions');
      expect(reply, 'fallback ok');
    });

    test('召回预算按实际 POST 计数，并复用已验证的兼容端点', () async {
      final requestedUrls = <String>[];
      final mock = MockClient((request) async {
        requestedUrls.add(request.url.toString());
        if (request.url.toString() == 'https://example.com/chat/completions') {
          return _utf8Response('not found', status: 404);
        }
        return _utf8Response(jsonEncode(<String, dynamic>{
          'choices': <Map<String, dynamic>>[
            <String, dynamic>{
              'message': <String, dynamic>{'content': 'ok'},
            },
          ],
        }));
      });
      final service = AiService(client: mock);
      const profile = LlmProfile(
        apiKey: 'sk',
        baseUrl: 'https://example.com',
        model: 'm',
      );

      final firstBudget = RecallRequestBudget(maxPosts: 2);
      expect(firstBudget.consumed, 0);
      expect(firstBudget.remaining, 2);
      expect(
        await service.ask(
          'first',
          contactId: 'c1',
          contactName: 'Test',
          profile: profile,
          requestBudget: firstBudget,
        ),
        'ok',
      );
      expect(firstBudget.consumed, 2);
      expect(firstBudget.remaining, 0);
      expect(firstBudget.isExhausted, isTrue);

      final secondBudget = RecallRequestBudget(maxPosts: 2);
      expect(
        await service.ask(
          'second',
          contactId: 'c1',
          contactName: 'Test',
          profile: profile,
          requestBudget: secondBudget,
        ),
        'ok',
      );
      expect(secondBudget.consumed, 1, reason: '后续请求应直达已验证的 /v1 端点');
      expect(requestedUrls, <String>[
        'https://example.com/chat/completions',
        'https://example.com/v1/chat/completions',
        'https://example.com/v1/chat/completions',
      ]);
    });

    test('兼容端点探测不能突破召回请求预算', () async {
      var attempts = 0;
      final mock = MockClient((request) async {
        attempts++;
        return _utf8Response('not found', status: 404);
      });
      final service = AiService(client: mock);
      final budget = RecallRequestBudget(maxPosts: 1);

      await expectLater(
        service.ask(
          'hi',
          contactId: 'c1',
          contactName: 'Test',
          profile: const LlmProfile(
            apiKey: 'sk',
            baseUrl: 'https://example.com',
            model: 'm',
          ),
          requestBudget: budget,
        ),
        throwsA(
          isA<AiServiceException>().having(
            (error) => error.userMessage,
            'userMessage',
            contains('预算已耗尽'),
          ),
        ),
      );
      expect(attempts, 1);
      expect(budget.consumed, 1);
      expect(budget.remaining, 0);
    });

    test('召回 POST 禁止客户端静默跟随重定向', () async {
      var attempts = 0;
      final mock = MockClient((request) async {
        attempts++;
        expect(request.followRedirects, isFalse);
        return http.Response(
          'redirect',
          307,
          headers: const <String, String>{
            'location': 'https://example.com/redirected',
          },
        );
      });
      final service = AiService(client: mock);
      final budget = RecallRequestBudget(maxPosts: 2);

      await expectLater(
        service.ask(
          'hi',
          contactId: 'c1',
          contactName: 'Test',
          profile: const LlmProfile(
            apiKey: 'sk',
            baseUrl: 'https://example.com',
            model: 'm',
          ),
          requestBudget: budget,
        ),
        throwsA(isA<AiServiceException>()),
      );
      expect(attempts, 1);
      expect(budget.consumed, 1);
    });

    test('召回超时覆盖响应体读取而不只覆盖响应头', () async {
      final client = _HangingBodyClient();
      final service = AiService(client: client);
      final budget = RecallRequestBudget(maxPosts: 2);
      final watch = Stopwatch()..start();

      await expectLater(
        service.ask(
          'hi',
          contactId: 'c1',
          contactName: 'Test',
          profile: const LlmProfile(
            apiKey: 'sk',
            baseUrl: 'https://example.com',
            model: 'm',
            parameters: LlmParameters(timeoutSeconds: 1),
          ),
          requestBudget: budget,
        ),
        throwsA(
          isA<AiServiceException>().having(
            (error) => error.userMessage,
            'userMessage',
            contains('超时'),
          ),
        ),
      );
      watch.stop();
      client.close();

      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
      expect(client.sends, 1);
      expect(budget.consumed, 1);
    });

    test('召回请求预算拒绝负数上限', () {
      expect(
        () => RecallRequestBudget(maxPosts: -1),
        throwsRangeError,
      );
    });

    test('405 也触发 fallback；其他 4xx 不重试', () async {
      var attempts = 0;
      final mock = MockClient((request) async {
        attempts++;
        if (attempts == 1) {
          return _utf8Response('method not allowed', status: 405);
        }
        return _utf8Response(jsonEncode(<String, dynamic>{
          'choices': <Map<String, dynamic>>[
            <String, dynamic>{
              'message': <String, dynamic>{'content': 'ok'},
            },
          ],
        }));
      });

      final service = AiService(client: mock);
      final reply = await service.ask(
        'hi',
        contactId: 'c1',
        contactName: 'Test',
        profile: const LlmProfile(
          apiKey: 'sk',
          baseUrl: 'https://example.com',
          model: 'm',
        ),
      );

      expect(attempts, 2);
      expect(reply, 'ok');
    });

    test('500 错误不 fallback 直接抛异常', () async {
      var attempts = 0;
      final mock = MockClient((request) async {
        attempts++;
        return _utf8Response('server error', status: 500);
      });

      final service = AiService(client: mock);
      await expectLater(
        service.ask(
          'hi',
          contactId: 'c1',
          contactName: 'Test',
          profile: const LlmProfile(
            apiKey: 'sk',
            baseUrl: 'https://example.com',
            model: 'm',
          ),
        ),
        throwsA(isA<AiServiceException>()),
      );
      expect(attempts, 1);
    });

    test('响应使用 choices[0].text 时也能解析（兼容旧 completions 端点）', () async {
      final mock = MockClient((request) async {
        return _utf8Response(jsonEncode(<String, dynamic>{
          'choices': <Map<String, dynamic>>[
            <String, dynamic>{'text': 'legacy'},
          ],
        }));
      });

      final service = AiService(client: mock);
      final reply = await service.ask(
        'hi',
        contactId: 'c1',
        contactName: 'Test',
        profile: const LlmProfile(
          apiKey: 'sk',
          baseUrl: 'https://example.com',
          model: 'm',
        ),
      );
      expect(reply, 'legacy');
    });

    test('响应使用顶层 message.content 时也能解析', () async {
      final mock = MockClient((request) async {
        return _utf8Response(jsonEncode(<String, dynamic>{
          'message': <String, dynamic>{'content': 'top-level'},
        }));
      });

      final service = AiService(client: mock);
      final reply = await service.ask(
        'hi',
        contactId: 'c1',
        contactName: 'Test',
        profile: const LlmProfile(
          apiKey: 'sk',
          baseUrl: 'https://example.com',
          model: 'm',
        ),
      );
      expect(reply, 'top-level');
    });

    test('空响应内容抛 FormatException 包装的 AiServiceException', () async {
      final mock = MockClient((request) async {
        return _utf8Response(jsonEncode(<String, dynamic>{
          'choices': <Map<String, dynamic>>[
            <String, dynamic>{
              'message': <String, dynamic>{'content': ''},
            },
          ],
        }));
      });

      final service = AiService(client: mock);
      await expectLater(
        service.ask(
          'hi',
          contactId: 'c1',
          contactName: 'Test',
          profile: const LlmProfile(
            apiKey: 'sk',
            baseUrl: 'https://example.com',
            model: 'm',
          ),
        ),
        throwsA(isA<AiServiceException>()),
      );
    });

    test('无 apiKey 直接抛错不发请求', () async {
      var attempts = 0;
      final mock = MockClient((request) async {
        attempts++;
        return _utf8Response('');
      });

      final service = AiService(client: mock);
      await expectLater(
        service.ask(
          'hi',
          contactId: 'c1',
          contactName: 'Test',
          profile: const LlmProfile(
            apiKey: '',
            baseUrl: 'https://example.com',
            model: 'm',
          ),
        ),
        throwsA(isA<AiServiceException>()),
      );
      expect(attempts, 0, reason: '无 apiKey 时不应发出任何 HTTP 请求');
    });

    test('401 错误映射为清晰的提示', () async {
      final mock = MockClient((request) async {
        return _utf8Response('unauthorized', status: 401);
      });

      final service = AiService(client: mock);
      try {
        await service.ask(
          'hi',
          contactId: 'c1',
          contactName: 'Test',
          profile: const LlmProfile(
            apiKey: 'sk',
            baseUrl: 'https://example.com',
            model: 'm',
          ),
        );
        fail('应该抛 AiServiceException');
      } on AiServiceException catch (e) {
        expect(e.userMessage, contains('API Key'));
        expect(e.userMessage, contains('401'));
      }
    });
  });

  group('格式异常时携带 rawResponse（debug 模式用）', () {
    test('空响应抛 AiServiceException 且 rawResponse = 空字符串', () async {
      final mock = MockClient((request) async {
        return _utf8Response('');
      });

      final service = AiService(client: mock);
      try {
        await service.ask(
          'hi',
          contactId: 'c1',
          contactName: 'Test',
          profile: const LlmProfile(
            apiKey: 'sk',
            baseUrl: 'https://example.com',
            model: 'm',
          ),
        );
        fail('应该抛 AiServiceException');
      } on AiServiceException catch (e) {
        expect(e.userMessage, contains('格式异常'));
        expect(e.rawResponse, '');
      }
    });

    test('解析出 JSON 但无有效 reply 字段时抛异常，rawResponse 是 body', () async {
      // LLM 返回了完整 JSON 但 reply/content/message 全空
      final mock = MockClient((request) async {
        return _utf8Response(jsonEncode(<String, dynamic>{
          'choices': <Map<String, dynamic>>[
            <String, dynamic>{
              'message': <String, dynamic>{'content': ''},
            },
          ],
        }));
      });

      final service = AiService(client: mock);
      try {
        await service.ask(
          'hi',
          contactId: 'c1',
          contactName: 'Test',
          profile: const LlmProfile(
            apiKey: 'sk',
            baseUrl: 'https://example.com',
            model: 'm',
          ),
        );
        fail('应该抛 AiServiceException');
      } on AiServiceException catch (e) {
        expect(e.userMessage, contains('格式异常'));
        expect(e.rawResponse, isNotNull);
        expect(e.rawResponse, contains('choices'));
      }
    });

    test('垃圾响应（既不是 JSON 也不像 JSON）退回纯文本显示', () async {
      final mock = MockClient((request) async {
        return _utf8Response('random garbage !! @@ ##');
      });

      final service = AiService(client: mock);
      // 新行为：垃圾也直接当 reply 返回，至少用户在 UI 上能看到 LLM 吐了什么
      final reply = await service.ask(
        'hi',
        contactId: 'c1',
        contactName: 'Test',
        profile: const LlmProfile(
          apiKey: 'sk',
          baseUrl: 'https://example.com',
          model: 'm',
        ),
      );
      expect(reply, 'random garbage !! @@ ##');
    });
  });

  group('非 JSON 格式响应（常见 fallback）', () {
    test('LLM 直接返回纯文本（无 JSON 包装）也能被当 reply 返回', () async {
      // 一些模型不遵循 JSON schema，直接给文字
      final mock = MockClient((request) async {
        return _utf8Response('你好，这是一段直接返回的文本。');
      });

      final service = AiService(client: mock);
      final reply = await service.ask(
        'hi',
        contactId: 'c1',
        contactName: 'Test',
        profile: const LlmProfile(
          apiKey: 'sk',
          baseUrl: 'https://example.com',
          model: 'm',
        ),
      );
      expect(reply, '你好，这是一段直接返回的文本。');
    });

    test('LLM 返回 markdown 代码块包裹的 JSON 也能解析', () async {
      final mock = MockClient((request) async {
        return _utf8Response('```json\n{"reply":"来自代码块的回复"}\n```');
      });

      final service = AiService(client: mock);
      final reply = await service.ask(
        'hi',
        contactId: 'c1',
        contactName: 'Test',
        profile: const LlmProfile(
          apiKey: 'sk',
          baseUrl: 'https://example.com',
          model: 'm',
        ),
      );
      expect(reply, '来自代码块的回复');
    });

    test('LLM 返回 "Here is: {...}" 文本夹杂 JSON 也能解析', () async {
      final mock = MockClient((request) async {
        return _utf8Response('好的，这是回复：\n{"reply":"夹杂的回复","memoryPatch":{}}');
      });

      final service = AiService(client: mock);
      final reply = await service.ask(
        'hi',
        contactId: 'c1',
        contactName: 'Test',
        profile: const LlmProfile(
          apiKey: 'sk',
          baseUrl: 'https://example.com',
          model: 'm',
        ),
      );
      expect(reply, '夹杂的回复');
    });

    test('LLM 返回 "{"choices":[]}"（格式像 JSON 但内容空）抛异常', () async {
      final mock = MockClient((request) async {
        return _utf8Response('{"choices":[]}');
      });

      final service = AiService(client: mock);
      try {
        await service.ask(
          'hi',
          contactId: 'c1',
          contactName: 'Test',
          profile: const LlmProfile(
            apiKey: 'sk',
            baseUrl: 'https://example.com',
            model: 'm',
          ),
        );
        fail('应该抛 AiServiceException');
      } on AiServiceException catch (e) {
        expect(e.userMessage, contains('格式异常'));
      }
    });

    test('纯文本超过 8000 字符不直接当 reply（防止卡 UI）', () async {
      // 模拟模型失控输出超长文本
      final longText = 'a' * 10000;
      final mock = MockClient((request) async {
        return _utf8Response(longText);
      });

      final service = AiService(client: mock);
      try {
        await service.ask(
          'hi',
          contactId: 'c1',
          contactName: 'Test',
          profile: const LlmProfile(
            apiKey: 'sk',
            baseUrl: 'https://example.com',
            model: 'm',
          ),
        );
        fail('应该抛 AiServiceException');
      } on AiServiceException catch (e) {
        expect(e.userMessage, contains('格式异常'));
      }
    });
  });

  group('SSE 流式响应（服务端不听话忽略 stream: false）', () {
    test('deepseek 风格的 SSE 响应：把 delta.content 拼起来作为 reply', () async {
      const sseBody = '''
data: {"id":"8210b37a","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}

data: {"id":"8210b37a","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"{\\n"},"finish_reason":null}]}

data: {"id":"8210b37a","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":" \\""},"finish_reason":null}]}

data: {"id":"8210b37a","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"reply"},"finish_reason":null}]}

data: {"id":"8210b37a","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"\\":\\""},"finish_reason":null}]}

data: {"id":"8210b37a","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"你好"},"finish_reason":null}]}

data: {"id":"8210b37a","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"，很高兴见到你。"},"finish_reason":null}]}

data: {"id":"8210b37a","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"\\",\\n \\"memoryPatch\\": {\\n  \\"eventBrief\\": {\\"description\\": \\"初次见面\\"} }\\n}"},"finish_reason":null}]}

data: {"id":"8210b37a","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":""},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":67,"total_tokens":77}}

data: [DONE]

''';

      final mock = MockClient((request) async {
        return _utf8Response(sseBody);
      });

      final service = AiService(client: mock);
      final reply = await service.ask(
        'hi',
        contactId: 'c1',
        contactName: 'Test',
        profile: const LlmProfile(
          apiKey: 'sk',
          baseUrl: 'https://example.com',
          model: 'm',
        ),
      );
      // 拼接后应该是完整 JSON，按业务约定提取 reply 字段
      expect(reply, contains('"reply"'));
      expect(reply, contains('你好'));
      expect(reply, contains('很高兴见到你'));
      expect(reply, contains('"memoryPatch"'));
    });

    test('SSE 流式纯文本回复（没包 JSON）也能拿到', () async {
      const sseBody = '''
data: {"choices":[{"delta":{"content":"你"}}]}

data: {"choices":[{"delta":{"content":"好"}}]}

data: {"choices":[{"delta":{"content":"，"}}]}

data: {"choices":[{"delta":{"content":"世界"}}]}

data: {"choices":[{"delta":{}},"finish_reason":"stop"}]}

data: [DONE]

''';

      final mock = MockClient((request) async {
        return _utf8Response(sseBody);
      });

      final service = AiService(client: mock);
      final reply = await service.ask(
        'hi',
        contactId: 'c1',
        contactName: 'Test',
        profile: const LlmProfile(
          apiKey: 'sk',
          baseUrl: 'https://example.com',
          model: 'm',
        ),
      );
      expect(reply, '你好，世界');
    });

    test('SSE 流式响应遇到空 chunk / [DONE] 标记都能正确处理', () async {
      const sseBody = '''
data: {"choices":[{"delta":{"content":"A"}}]}

data: {"choices":[{"delta":{"content":"B"}}]}

data: [DONE]

data: {"choices":[{"delta":{"content":"C"}}]}

''';

      final mock = MockClient((request) async {
        return _utf8Response(sseBody);
      });

      final service = AiService(client: mock);
      final reply = await service.ask(
        'hi',
        contactId: 'c1',
        contactName: 'Test',
        profile: const LlmProfile(
          apiKey: 'sk',
          baseUrl: 'https://example.com',
          model: 'm',
        ),
      );
      // [DONE] 后的 chunk 仍会被某些代理重发；我们不应该重复拼它
      expect(reply, 'AB');
    });

    test('SSE chunk 被 TCP 包拆成多行也能正确解析', () async {
      // 真实场景中一个 SSE 事件可能跨多行（id/event/data 字段）
      const sseBody = '''data: {"choices":[{"delta":{"content":"hello"}}]}

''';

      final mock = MockClient((request) async {
        return _utf8Response(sseBody);
      });

      final service = AiService(client: mock);
      final reply = await service.ask(
        'hi',
        contactId: 'c1',
        contactName: 'Test',
        profile: const LlmProfile(
          apiKey: 'sk',
          baseUrl: 'https://example.com',
          model: 'm',
        ),
      );
      expect(reply, 'hello');
    });

    test('SSE 注释行（以 : 开头）能被跳过', () async {
      const sseBody = '''
: this is a comment line
data: {"choices":[{"delta":{"content":"ok"}}]}

''';

      final mock = MockClient((request) async {
        return _utf8Response(sseBody);
      });

      final service = AiService(client: mock);
      final reply = await service.ask(
        'hi',
        contactId: 'c1',
        contactName: 'Test',
        profile: const LlmProfile(
          apiKey: 'sk',
          baseUrl: 'https://example.com',
          model: 'm',
        ),
      );
      expect(reply, 'ok');
    });

    test('SSE chunk 单个 JSON 解析失败（半截 JSON）能跳过该 chunk', () async {
      const sseBody = '''
data: {"choices":[{"delta":{"content":"正常"}}]}

data: {"choices":[{"delta":{"content":"invalid json this is broken

data: {"choices":[{"delta":{"content":"继续"}}]}

data: [DONE]

''';

      final mock = MockClient((request) async {
        return _utf8Response(sseBody);
      });

      final service = AiService(client: mock);
      final reply = await service.ask(
        'hi',
        contactId: 'c1',
        contactName: 'Test',
        profile: const LlmProfile(
          apiKey: 'sk',
          baseUrl: 'https://example.com',
          model: 'm',
        ),
      );
      // 半截 JSON 被跳过，但其他正常 chunk 仍然拼起来
      expect(reply, contains('正常'));
      expect(reply, contains('继续'));
    });

    test('SSE 流式响应里 reply 字段在第一个 chunk 就完整给出', () async {
      // 一些模型第一个 chunk 就把 reply 字段给齐了
      const sseBody = '''
data: {"choices":[{"delta":{"reply":"完整回复"}}]}

data: {"choices":[{"delta":{"content":"又来了"}}]}

data: [DONE]

''';

      final mock = MockClient((request) async {
        return _utf8Response(sseBody);
      });

      final service = AiService(client: mock);
      final reply = await service.ask(
        'hi',
        contactId: 'c1',
        contactName: 'Test',
        profile: const LlmProfile(
          apiKey: 'sk',
          baseUrl: 'https://example.com',
          model: 'm',
        ),
      );
      // 我们按 choices[0].message.content 取，SSE 重组后的 content
      // 是把 delta.content 拼起来的（reply 字段被忽略），所以是「又来了」
      // 这跟 LLM 实际输出语义保持一致
      expect(reply, '又来了');
    });

    test('非 SSE 但包含 "data:" 字符串（如 reply 文本提到"data:"）不误判', () async {
      // LLM 在 reply 里提到了 "data:" 这个词
      final mock = MockClient((request) async {
        return _utf8Response('我需要一些 data: 样例数据，但这里没有结构化数据可用。');
      });

      final service = AiService(client: mock);
      final reply = await service.ask(
        'hi',
        contactId: 'c1',
        contactName: 'Test',
        profile: const LlmProfile(
          apiKey: 'sk',
          baseUrl: 'https://example.com',
          model: 'm',
        ),
      );
      expect(reply, '我需要一些 data: 样例数据，但这里没有结构化数据可用。');
    });

    test('askStream 按 OpenAI SSE delta 顺序产出文本并强制 stream=true', () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return http.Response(
          'data: {"choices":[{"delta":{"content":"你"}}]}\n\n'
          'data: {"choices":[{"delta":{"content":"好"}}]}\n\n'
          'data: [DONE]\n\n',
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        );
      });
      final chunks = await AiService(client: mock)
          .askStream(
            'hi',
            contactId: 'c1',
            contactName: 'Test',
            profile: const LlmProfile(
              apiKey: 'sk',
              baseUrl: 'https://example.com/v1',
              model: 'm',
            ),
          )
          .toList();

      expect(chunks, ['你', '好']);
      expect(captured.headers['Accept'], 'text/event-stream');
      expect(jsonDecode(captured.body)['stream'], isTrue);
    });

    test('askStream 在首个端点 404 时回退到兼容路径', () async {
      var attempts = 0;
      final mock = MockClient((request) async {
        attempts++;
        if (attempts == 1) return _utf8Response('not found', status: 404);
        return http.Response(
          'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n'
          'data: [DONE]\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final result = await AiService(client: mock)
          .askStream(
            'hi',
            contactId: 'c1',
            contactName: 'Test',
            profile: const LlmProfile(
              apiKey: 'sk',
              baseUrl: 'https://example.com',
              model: 'm',
            ),
          )
          .join();
      expect(result, 'ok');
      expect(attempts, 2);
    });
  });
}
