import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/llm_config.dart';

/// 用途绑定：记录每个功能用的是哪个配置下的哪个模型
class UsageBinding {
  final String configId;
  final String modelId;
  const UsageBinding({required this.configId, required this.modelId});

  Map<String, dynamic> toJson() => {'configId': configId, 'modelId': modelId};
  factory UsageBinding.fromJson(Map<String, dynamic> json) => UsageBinding(
        configId: json['configId']?.toString() ?? '',
        modelId: json['modelId']?.toString() ?? '',
      );
}

class LLMConfigStore {
  static const _key = 'llm_configs';
  static const _usageBindingKey = 'usage_bindings_v2';

  /// 内存缓存，供同步方法（UI 检查）使用
  static Map<String, UsageBinding> _cachedBindings = {};
  static Map<String, UsageBinding> get cachedBindings => _cachedBindings;

  // ==================== 配置 CRUD ====================
  Future<void> saveAll(List<LLMConfig> configs) async {
    final sp = await SharedPreferences.getInstance();
    final data = configs.map((e) => e.toJson()).toList();
    await sp.setString(_key, jsonEncode(data));
  }

  Future<List<LLMConfig>> loadAll() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => LLMConfig.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  // ==================== 绑定 CRUD ====================
  Future<Map<String, UsageBinding>> getBindings() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_usageBindingKey);
    if (raw == null || raw.isEmpty) {
      _cachedBindings = {};
      return {};
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final result = <String, UsageBinding>{};
      map.forEach((key, value) {
        if (value is Map) {
          result[key] = UsageBinding.fromJson(Map<String, dynamic>.from(value));
        }
      });
      _cachedBindings = result;
      return result;
    } catch (_) {
      _cachedBindings = {};
      return {};
    }
  }

  /// 在 App 启动时调用一次，把绑定读进内存，供同步检查使用
  static Future<void> preloadBindings() async {
    await LLMConfigStore().getBindings();
  }

  /// 绑定用途到指定配置的具体模型
  /// usage 取值: chat / vision / image / video
  Future<void> setActiveConfig(String usage, String configId, String modelId) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_usageBindingKey);
    Map<String, dynamic> bindings = {};
    if (raw != null && raw.isNotEmpty) {
      try {
        bindings = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }
    bindings[usage] = {'configId': configId, 'modelId': modelId};
    await sp.setString(_usageBindingKey, jsonEncode(bindings));
    _cachedBindings[usage] = UsageBinding(configId: configId, modelId: modelId);
  }

  /// 获取指定用途绑定的配置对象
  Future<LLMConfig?> getActiveConfig(String usage) async {
    final bindings = await getBindings();
    final binding = bindings[usage];
    if (binding == null) return null;
    final all = await loadAll();
    for (final c in all) {
      if (c.id == binding.configId) return c;
    }
    return null;
  }

  /// 获取指定用途绑定的具体模型 ID
  Future<String?> getActiveModelId(String usage) async {
    final bindings = await getBindings();
    return bindings[usage]?.modelId;
  }

  /// 清除某个用途的绑定
  Future<void> clearBinding(String usage) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_usageBindingKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final bindings = jsonDecode(raw) as Map<String, dynamic>;
      bindings.remove(usage);
      await sp.setString(_usageBindingKey, jsonEncode(bindings));
      _cachedBindings.remove(usage);
    } catch (_) {}
  }
}