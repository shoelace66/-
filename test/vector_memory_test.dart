import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/core/utils/vector_memory_service.dart';

void main() {
  late VectorMemoryService vectorMemoryService;
  const String testContactId1 = 'contact-001';
  const String testContactId2 = 'contact-002';

  setUp(() async {
    vectorMemoryService = VectorMemoryService();
    await vectorMemoryService.initialize();
    await vectorMemoryService.clearAll();
  });

  tearDown(() async {
    await vectorMemoryService.clearAll();
  });

  test('测试向量存储服务初始化', () async {
    expect(vectorMemoryService, isNotNull);
  });

  test('测试添加和检索记忆条目', () async {
    // 添加测试数据
    await vectorMemoryService.addMemoryEntry(
      '1',
      '我们在旧城区钟楼调查停电异常',
      'event',
      contactId: testContactId1,
    );
    await vectorMemoryService.addMemoryEntry(
      '2',
      '用户喜欢先看证据再下结论',
      'user_knowledge',
      contactId: testContactId1,
    );
    await vectorMemoryService.addMemoryEntry(
      '3',
      '我擅长记录线索',
      'self_knowledge',
      contactId: testContactId1,
    );

    // 测试检索
    final results = await vectorMemoryService.searchSimilar(
      '调查异常',
      2,
      contactId: testContactId1,
    );
    expect(results.length, 2);
    expect(results[0].entry.content, contains('调查'));
  });

  test('测试按类型检索', () async {
    // 添加测试数据
    await vectorMemoryService.addMemoryEntry(
      '1',
      '我们在旧城区钟楼调查停电异常',
      'event',
      contactId: testContactId1,
    );
    await vectorMemoryService.addMemoryEntry(
      '2',
      '用户喜欢先看证据再下结论',
      'user_knowledge',
      contactId: testContactId1,
    );

    // 测试按类型检索
    final eventResults = await vectorMemoryService.searchSimilar(
      '调查',
      2,
      type: 'event',
      contactId: testContactId1,
    );
    expect(eventResults.length, 1);
    expect(eventResults[0].entry.type, 'event');

    final userResults = await vectorMemoryService.searchSimilar(
      '用户',
      2,
      type: 'user_knowledge',
      contactId: testContactId1,
    );
    expect(userResults.length, 1);
    expect(userResults[0].entry.type, 'user_knowledge');
  });

  test('测试语义相似度计算', () async {
    // 添加测试数据
    await vectorMemoryService.addMemoryEntry(
      '1',
      '我们在旧城区钟楼调查停电异常',
      'event',
      contactId: testContactId1,
    );
    await vectorMemoryService.addMemoryEntry(
      '2',
      '我们在老城区钟塔检查电力故障',
      'event',
      contactId: testContactId1,
    );
    await vectorMemoryService.addMemoryEntry(
      '3',
      '今天天气很好',
      'event',
      contactId: testContactId1,
    );

    // 测试语义相似度
    final results = await vectorMemoryService.searchSimilar(
      '电力问题',
      3,
      contactId: testContactId1,
    );
    expect(results.length, 3);
    expect(results[0].entry.content, contains('电力'));
    expect(results[1].entry.content, contains('停电'));
    expect(results[2].entry.content, contains('天气'));
  });

  test('测试联系人数据隔离 - 不同联系人的数据互不干扰', () async {
    // 为联系人1添加数据
    await vectorMemoryService.addMemoryEntry(
      'msg-1',
      '联系人1的消息内容',
      'message',
      contactId: testContactId1,
    );

    // 为联系人2添加数据
    await vectorMemoryService.addMemoryEntry(
      'msg-2',
      '联系人2的消息内容',
      'message',
      contactId: testContactId2,
    );

    // 搜索联系人1的数据，应该只返回联系人1的结果
    final results1 = await vectorMemoryService.searchSimilar(
      '消息',
      10,
      contactId: testContactId1,
    );
    expect(results1.length, 1);
    expect(results1[0].entry.content, contains('联系人1'));
    expect(results1[0].entry.contactId, testContactId1);

    // 搜索联系人2的数据，应该只返回联系人2的结果
    final results2 = await vectorMemoryService.searchSimilar(
      '消息',
      10,
      contactId: testContactId2,
    );
    expect(results2.length, 1);
    expect(results2[0].entry.content, contains('联系人2'));
    expect(results2[0].entry.contactId, testContactId2);
  });

  test('测试删除联系人数据', () async {
    // 为两个联系人添加数据
    await vectorMemoryService.addMemoryEntry(
      'msg-1',
      '联系人1的消息',
      'message',
      contactId: testContactId1,
    );
    await vectorMemoryService.addMemoryEntry(
      'msg-2',
      '联系人1的另一条消息',
      'message',
      contactId: testContactId1,
    );
    await vectorMemoryService.addMemoryEntry(
      'msg-3',
      '联系人2的消息',
      'message',
      contactId: testContactId2,
    );

    // 删除联系人1的所有数据
    await vectorMemoryService.deleteContactMemories(testContactId1);

    // 验证联系人1的数据已被删除
    final results1 = await vectorMemoryService.searchSimilar(
      '消息',
      10,
      contactId: testContactId1,
    );
    expect(results1.length, 0);

    // 验证联系人2的数据仍然存在
    final results2 = await vectorMemoryService.searchSimilar(
      '消息',
      10,
      contactId: testContactId2,
    );
    expect(results2.length, 1);
    expect(results2[0].entry.content, contains('联系人2'));
  });
}
