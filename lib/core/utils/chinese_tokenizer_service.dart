import 'package:jieba_flutter/analysis/jieba_segmenter.dart';
import 'package:jieba_flutter/analysis/seg_token.dart';

/// 中文分词服务
///
/// 基于jieba_flutter实现的中文分词器，提供类似Python jieba的分词功能
/// 支持精确模式、全模式和搜索引擎模式
class ChineseTokenizerService {
  // ==================== 单例实现 ====================

  static final ChineseTokenizerService _instance =
      ChineseTokenizerService._internal();

  factory ChineseTokenizerService() => _instance;

  ChineseTokenizerService._internal();

  // ==================== 状态管理 ====================

  bool _initialized = false;

  // ==================== 初始化方法 ====================

  /// 初始化分词器
  ///
  /// 必须在应用启动时调用一次，加载分词词典
  Future<void> init() async {
    if (_initialized) return;
    await JiebaSegmenter.init();
    _initialized = true;
  }

  // ==================== 公共API：分词方法 ====================

  /// 精确模式分词
  ///
  /// 适合用于文本分析，将句子精确切分
  /// 返回分词结果列表，每个元素为词语字符串
  /// 过滤掉长度大于8字的词
  List<String> cut(String text) {
    _ensureInitialized();
    if (text.isEmpty) return [];

    final segmenter = JiebaSegmenter();
    final segments = segmenter.process(text, SegMode.SEARCH);

    return _filterByLength(segments);
  }

  /// 全模式分词
  ///
  /// 把句子中所有可能的词语都扫描出来，速度快但不能解决歧义
  /// 过滤掉长度大于8字的词
  List<String> cutAll(String text) {
    _ensureInitialized();
    if (text.isEmpty) return [];

    final segmenter = JiebaSegmenter();
    final segments = segmenter.process(text, SegMode.INDEX);

    return _filterByLength(segments);
  }

  /// 搜索引擎模式分词
  ///
  /// 在精确模式基础上，对长词再次切分，提高召回率
  /// 适合用于搜索引擎分词
  /// 过滤掉长度大于8字的词
  List<String> cutForSearch(String text) {
    _ensureInitialized();
    if (text.isEmpty) return [];

    final segmenter = JiebaSegmenter();
    final segments = segmenter.process(text, SegMode.SEARCH);

    return _filterByLength(segments);
  }

  /// 提取关键词
  ///
  /// 基于TF-IDF算法提取文本中的关键词
  /// [topK] 返回前topK个关键词
  List<String> extractKeywords(String text, {int topK = 8}) {
    _ensureInitialized();
    if (text.isEmpty) return [];

    final words = cut(text);
    final filteredWords = _filterStopWords(words);
    final wordFreq = _calculateWordFrequency(filteredWords);

    return _getTopKeywords(wordFreq, topK);
  }

  /// 添加自定义词典
  ///
  /// 可以添加领域特定的词汇，提高分词准确率
  /// 注意：jieba_flutter可能不支持动态添加词典，此方法预留
  void addWord(String word, {int freq = 1}) {
    _ensureInitialized();
    // jieba_flutter目前版本可能不支持动态添加词典
    // 此方法作为预留接口
  }

  // ==================== 私有辅助方法 ====================

  /// 确保服务已初始化
  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'ChineseTokenizerService未初始化，请先调用init()',
      );
    }
  }

  /// 按长度过滤分词结果
  List<String> _filterByLength(List<SegToken> tokens) {
    return tokens
        .map((token) => token.word)
        .where((word) => word.length <= 8)
        .toList();
  }

  /// 过滤停用词
  List<String> _filterStopWords(List<String> words) {
    return words
        .where((word) => word.length > 1)
        .where((word) => !_stopWords.contains(word.toLowerCase()))
        .toList();
  }

  /// 统计词频
  Map<String, int> _calculateWordFrequency(List<String> words) {
    final wordFreq = <String, int>{};
    for (final word in words) {
      wordFreq[word] = (wordFreq[word] ?? 0) + 1;
    }
    return wordFreq;
  }

  /// 获取TopK关键词
  List<String> _getTopKeywords(Map<String, int> wordFreq, int topK) {
    final sortedEntries = wordFreq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sortedEntries.take(topK).map((e) => e.key).toList();
  }

  // ==================== 常量定义 ====================

  /// 停用词表
  /// 包含：虚词、代词、助词、常见动词、形容词、副词、数量词等
  static const Set<String> _stopWords = {
    // ========== 中文虚词/助词/语气词 ==========
    '的', '了', '在', '是', '有', '和', '就', '不', '都', '上', '也', '到', '说',
    '要', '去', '会', '着', '没有', '看', '这', '那', '啊', '呢', '吧', '吗',
    '哦', '嗯', '哈', '呀', '哇', '哪', '啦', '呗', '嘛', '咯', '呐', '兮',
    '之', '乎', '者', '亦', '矣', '焉', '哉', '与', '及', '而', '或', '但',
    '若', '虽', '则', '乃', '即', '便', '因', '为', '所以',
    '因为', '因此', '于是', '而且', '并且', '或者', '还是', '要么',
    '被', '把', '将', '让', '给', '叫', '使', '令', '由', '从', '向', '往',
    '对', '对于', '关于', '至于', '根据', '按照', '通过', '经过',

    // ========== 中文代词 ==========
    '我', '你', '他', '她', '它', '我们', '你们', '他们', '她们', '它们',
    '咱们', '大家', '人家', '别人', '旁人', '自己', '本人',
    '这里', '那里', '这边', '那边', '这儿', '那儿', '这边儿', '那边儿',
    '这个', '那个', '这些', '那些', '这样', '那样', '这么', '那么',
    '谁', '什么', '哪个', '哪些', '哪里', '哪儿', '几时', '多少',
    '怎么', '怎样', '怎么样', '如何', '为什么', '为何',
    '一切', '所有', '任何', '有的', '有些', '某个', '某些', '其他', '其余',

    // ========== 中文数量词 ==========
    '一', '二', '三', '四', '五', '六', '七', '八', '九', '十',
    '百', '千', '万', '亿', '两', '几', '半', '双', '整',
    '个', '位', '种', '样', '类', '点', '部分',
    '第一', '第二', '第三', '最后', '更', '比较', '非常',
    '一个', '一种', '一些', '一点', '一方面', '一直',

    // ========== 中文常见动词（高频无实义） ==========
    '来', '走', '跑', '吃', '喝', '睡', '醒', '坐', '站',
    '躺', '卧', '趴', '蹲', '跪', '跳', '飞', '游', '爬',
    '拿', '送', '接', '打', '开', '关', '放', '取', '找',
    '抓', '握', '抱', '背', '扛', '抬', '举', '推', '拉', '拖',
    '做', '搞', '弄', '办', '处理', '进行', '完成', '实现', '执行',
    '想', '认为', '知道', '了解', '明白', '懂得', '记得', '忘记',
    '感觉', '感到', '以为', '猜测', '估计', '预料',
    '望', '瞧', '盯', '瞪', '瞄', '瞥', '扫',
    '听到', '听见', '闻', '嗅', '尝', '摸', '触',
    '问', '回答', '告诉', '讲', '谈', '聊', '道', '言', '语',
    '利用', '采用', '应用', '运用', '借',
    '邀请', '请求', '要求', '命令', '指示', '吩咐',
    '能够', '可以', '可能', '须', '必要',
    '应', '应当', '该当', '值得', '配', '够',
    '喜欢', '爱', '恨', '讨厌', '愿意', '肯', '敢', '乐于',

    // ========== 中文常见形容词/副词 ==========
    '好', '坏', '大', '小', '多', '少', '高', '低', '长', '短',
    '快', '慢', '早', '晚', '新', '旧', '老', '轻', '重',
    '热', '冷', '暖', '凉', '干', '湿', '软', '硬', '粗', '细',
    '厚', '薄', '深', '浅', '远', '近',
    '红', '黄', '蓝', '绿', '白', '黑', '灰', '紫', '粉', '青',
    '亮', '暗', '明', '淡', '浓', '鲜', '艳', '素',
    '美', '丑', '漂亮', '难看', '帅', '俊', '靓',
    '香', '臭', '甜', '苦', '辣', '酸', '咸',
    '很', '太', '极', '挺', '真', '相当', '十分',
    '稍微', '有点', '几乎', '简直', '根本', '绝对',
    '又', '再', '还', '全', '总', '始终',
    '已经', '曾经', '就要', '马上', '立刻', '忽然', '突然',
    '常常', '经常', '往往', '一向', '永远',
    '也许', '或许', '大概', '大约', '约', '差不多',

    // ========== 中文方位/时间词 ==========
    '下', '左', '右', '前', '后', '里', '外', '内', '中',
    '间', '旁', '边', '面', '头', '部', '侧', '端', '底', '顶',
    '东', '西', '南', '北', '东南', '东北', '西南', '西北',
    '今天', '明天', '昨天', '后天', '前天',
    '现在', '当时', '以前', '以后', '后来', '之前', '之后',
    '刚才', '刚刚', '正在',
    '年', '月', '日', '天', '周', '星期', '小时', '分钟', '秒',
    '早晨', '早上', '上午', '中午', '下午', '晚上', '夜间', '深夜',
    '春天', '夏天', '秋天', '冬天', '春季', '夏季', '秋季', '冬季',

    // ========== 中文常见名词（过于宽泛） ==========
    '东西', '事情', '情况', '问题', '地方', '时候', '时间', '原因',
    '结果', '方法', '方式', '过程', '关系', '方面', '意义',
    '目的', '作用', '效果', '影响', '价值', '水平', '程度', '标准',
    '条件', '环境', '背景', '基础', '前提', '因素', '要素',
    '人', '人们', '人类', '人口', '人员', '人士', '人物',
    '事', '物', '处', '线', '体',

    // ========== 英文停用词 ==========
    'the', 'a', 'an',
    'am', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'have', 'has', 'had', 'having',
    'do', 'does', 'did', 'doing', 'done',
    'will', 'would', 'shall', 'should', 'can', 'could',
    'may', 'might', 'must', 'ought', 'need', 'dare', 'used',
    'i', 'me', 'my', 'myself', 'mine',
    'we', 'us', 'our', 'ours', 'ourselves',
    'you', 'your', 'yours', 'yourself', 'yourselves',
    'he', 'him', 'his', 'himself',
    'she', 'her', 'hers', 'herself',
    'it', 'its', 'itself',
    'they', 'them', 'their', 'theirs', 'themselves',
    'this', 'that', 'these', 'those',
    'what', 'which', 'who', 'whom', 'whose',
    'whatever', 'whichever', 'whoever', 'whomever',
    'and', 'but', 'or', 'yet', 'so', 'for', 'nor',
    'about', 'above', 'across', 'after', 'against', 'along',
    'among', 'around', 'at', 'before', 'behind', 'below', 'beneath',
    'beside', 'besides', 'between', 'beyond', 'by',
    'concerning', 'despite', 'down', 'during', 'except', 'excepting',
    'from', 'in', 'inside', 'into', 'like', 'near', 'of', 'off',
    'on', 'onto', 'out', 'outside', 'over', 'past', 'regarding',
    'round', 'since', 'through', 'throughout', 'till', 'to', 'toward',
    'towards', 'under', 'underneath', 'until', 'up', 'upon', 'with',
    'within', 'without',
    'as', 'than', 'too', 'very', 'just', 'now', 'only', 'also',
    'here', 'there', 'when', 'where', 'why', 'how', 'all', 'any',
    'both', 'each', 'few', 'more', 'most', 'other', 'some', 'such',
    'no', 'not', 'own', 'same',
  };
}
