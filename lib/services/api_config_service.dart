import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';
import 'llm_config_store.dart';

/// API 配置服务
/// 保留原有的老 Key 存储（为了兼容旧版本），同时新增动态绑定检查
class ApiConfigService {
  static const String _keyZhipuApiKey = 'zhipu_api_key';
  static const String _keyVideoApiKey = 'video_api_key';
  static const String _keyImageApiKey = 'image_api_key';
  static const String _keyDoubaoApiKey = 'doubao_api_key';
  static const String _unconfigured = '';

  static SharedPreferences? _prefs;
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
      // 预加载动态绑定到内存，供同步检查方法使用
      await LLMConfigStore.preloadBindings();
      AppLogger.success('ApiConfigService', 'API 配置服务初始化完成');
    } catch (e) {
      AppLogger.error('ApiConfigService', '初始化失败', e);
      rethrow;
    }
  }

  // ==================== 老 Key 存取（保留兼容） ====================
  static String getZhipuApiKey() { _ensureInitialized(); return _prefs!.getString(_keyZhipuApiKey) ?? _unconfigured; }
  static Future<void> setZhipuApiKey(String key) async { _ensureInitialized(); await _prefs!.setString(_keyZhipuApiKey, key); }

  static String getVideoApiKey() { _ensureInitialized(); return _prefs!.getString(_keyVideoApiKey) ?? _unconfigured; }
  static Future<void> setVideoApiKey(String key) async { _ensureInitialized(); await _prefs!.setString(_keyVideoApiKey, key); }

  static String getImageApiKey() { _ensureInitialized(); return _prefs!.getString(_keyImageApiKey) ?? _unconfigured; }
  static Future<void> setImageApiKey(String key) async { _ensureInitialized(); await _prefs!.setString(_keyImageApiKey, key); }

  static String getDoubaoApiKey() { _ensureInitialized(); return _prefs!.getString(_keyDoubaoApiKey) ?? _unconfigured; }
  static Future<void> setDoubaoApiKey(String key) async { _ensureInitialized(); await _prefs!.setString(_keyDoubaoApiKey, key); }

  // ==================== 动态绑定状态（新增，供 UI 检查用） ====================
  static bool isChatBound() => LLMConfigStore.cachedBindings.containsKey('chat');
  static bool isVisionBound() => LLMConfigStore.cachedBindings.containsKey('vision');
  static bool isImageBound() => LLMConfigStore.cachedBindings.containsKey('image');
  static bool isVideoBound() => LLMConfigStore.cachedBindings.containsKey('video');

  /// 刷新内存缓存（在设置页保存绑定时调用）
  static Future<void> refreshBindings() async {
    await LLMConfigStore().getBindings();
  }

  // ==================== 检查方法（改为读动态绑定） ====================

  static ApiConfigStatus checkRequiredKeys() {
    final missing = <String>[];
    if (!isChatBound()) missing.add('对话模型');
    if (!isVisionBound()) missing.add('视觉识别模型');
    if (!isImageBound()) missing.add('图像生成模型');
    if (!isVideoBound()) missing.add('视频生成模型');
    if (missing.isEmpty) return ApiConfigStatus.allConfigured;
    return ApiConfigStatus(isAllConfigured: false, missingKeys: missing);
  }

  static ApiConfigStatus checkChatKeys() {
    if (isChatBound()) return ApiConfigStatus.allConfigured;
    return const ApiConfigStatus(isAllConfigured: false, missingKeys: ['对话模型']);
  }

  static ApiConfigStatus checkVideoGenerationKeys() {
    final missing = <String>[];
    if (!isChatBound()) missing.add('对话模型');
    if (!isImageBound()) missing.add('图像生成模型');
    if (!isVideoBound()) missing.add('视频生成模型');
    if (missing.isEmpty) return ApiConfigStatus.allConfigured;
    return ApiConfigStatus(isAllConfigured: false, missingKeys: missing);
  }

  // ==================== 兼容旧 API ====================
  static bool isZhipuApiKeyConfigured() => isChatBound();
  static bool isVideoApiKeyConfigured() => isVideoBound();
  static bool isImageApiKeyConfigured() => isImageBound();
  static bool isDoubaoApiKeyConfigured() => isVisionBound();

  static Map<String, String> getAllConfigs() {
    _ensureInitialized();
    return {
      'zhipu': getZhipuApiKey(),
      'video': getVideoApiKey(),
      'image': getImageApiKey(),
      'doubao': getDoubaoApiKey(),
    };
  }

  static Future<void> setAllConfigs({
    required String zhipuKey,
    required String videoKey,
    required String imageKey,
    required String doubaoKey,
  }) async {
    _ensureInitialized();
    await _prefs!.setString(_keyZhipuApiKey, zhipuKey);
    await _prefs!.setString(_keyVideoApiKey, videoKey);
    await _prefs!.setString(_keyImageApiKey, imageKey);
    await _prefs!.setString(_keyDoubaoApiKey, doubaoKey);
  }

  static Future<void> clearAll() async {
    _ensureInitialized();
    await _prefs!.remove(_keyZhipuApiKey);
    await _prefs!.remove(_keyVideoApiKey);
    await _prefs!.remove(_keyImageApiKey);
    await _prefs!.remove(_keyDoubaoApiKey);
  }

  static void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('ApiConfigService 未初始化，请先调用 initialize()');
    }
  }

  static String maskApiKey(String key) {
    if (key.isEmpty) return '未设置';
    if (key.length <= 10) return '${key.substring(0, 4)}***';
    return '${key.substring(0, 8)}...${key.substring(key.length - 4)}';
  }
}

class ApiConfigStatus {
  final bool isAllConfigured;
  final List<String> missingKeys;
  const ApiConfigStatus({required this.isAllConfigured, this.missingKeys = const []});
  static const allConfigured = ApiConfigStatus(isAllConfigured: true);
  bool get isConfigured => isAllConfigured;
  int get missingCount => missingKeys.length;
  String? get firstMissing => missingKeys.isNotEmpty ? missingKeys.first : null;
  String get friendlyMessage => isAllConfigured ? '所有 API Key 已配置' : '缺少：${missingKeys.join('、')}';
}