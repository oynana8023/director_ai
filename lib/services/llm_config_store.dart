import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/llm_config.dart';

/// 大模型配置本地存储服务
class LLMConfigStore {
  // 存储所有自定义配置列表的 key
  static const _key = 'llm_configs';
  // 存储“用途 -> 配置ID”绑定关系的 key
  static const _usageBindingKey = 'usage_bindings';

  // ==================== 基础 CRUD ====================

  /// 保存所有配置
  Future<void> saveAll(List<LLMConfig> configs) async {
    final sp = await SharedPreferences.getInstance();
    final data = configs.map((e) => e.toJson()).toList();
    await sp.setString(_key, jsonEncode(data));
  }

  /// 读取所有配置
  Future<List<LLMConfig>> loadAll() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => LLMConfig.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  // ==================== 用途绑定 ====================

  /// 获取所有绑定关系，例如 {"chat": "config_id_xxx", "image": "config_id_yyy"}
  Future<Map<String, String>> getBindings() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_usageBindingKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((key, value) => MapEntry(key, value.toString()));
    } catch (e) {
      return {};
    }
  }

  /// 为指定用途绑定一个配置
  /// usage 取值: chat / vision / image / video
  Future<void> setActiveConfig(String usage, String configId) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_usageBindingKey);
    Map<String, dynamic> bindings = {};
    if (raw != null && raw.isNotEmpty) {
      try {
        bindings = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        bindings = {};
      }
    }
    bindings[usage] = configId;
    await sp.setString(_usageBindingKey, jsonEncode(bindings));
  }

  /// 获取指定用途当前绑定的配置对象，如果没绑定返回 null
  Future<LLMConfig?> getActiveConfig(String usage) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_usageBindingKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final bindings = jsonDecode(raw) as Map<String, dynamic>;
      final configId = bindings[usage]?.toString();
      if (configId == null || configId.isEmpty) return null;

      final allConfigs = await loadAll();
      for (final config in allConfigs) {
        if (config.id == configId) {
          return config;
        }
      }
      return null; // 配置被删除了
    } catch (e) {
      return null;
    }
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
    } catch (_) {}
  }
}