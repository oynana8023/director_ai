// lib/services/llm_config_store.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/llm_config.dart';

class LLMConfigStore {
  static const _key = 'llm_configs';

  // 1. 保存所有厂商配置到本地
  Future<void> saveAll(List<LLMConfig> configs) async {
    final sp = await SharedPreferences.getInstance();
    final data = configs.map((e) => e.toJson()).toList();
    await sp.setString(_key, jsonEncode(data));
  }

  // 2. 读取本地所有的厂商配置
  Future<List<LLMConfig>> loadAll() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => LLMConfig.fromJson(e)).toList();
    } catch (e) {
      // 防止本地数据损坏导致应用崩溃
      return [];
    }
  }
}