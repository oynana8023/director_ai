// lib/services/llm_provider.dart
import 'package:dio/dio.dart';
import '../models/llm_config.dart';

class LLMProvider {
  final LLMConfig config;
  late final Dio _dio;

  LLMProvider(this.config) {
    _dio = Dio(BaseOptions(
      baseUrl: config.baseUrl, // 注意：有些厂家baseUrl末尾带斜杠，有些没有，需要做处理
      headers: {
        'Authorization': 'Bearer ${config.apiKey}',
        'Content-Type': 'application/json',
      },
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    ));
  }

  // 1. 拉取可用模型列表 (GET /models)
  Future<List<String>> fetchModels() async {
    try {
      // 处理 baseUrl 可能的结尾斜杠问题
      String url = config.baseUrl.endsWith('/') 
          ? '${config.baseUrl}models' 
          : '${config.baseUrl}/models';
          
      final res = await _dio.get(url);
      
      // 兼容标准 OpenAI 格式
      if (res.data is Map && res.data['data'] is List) {
        return (res.data['data'] as List).map((e) => e['id'].toString()).toList();
      } 
      // 兼容部分厂商直接返回数组的格式
      else if (res.data is List) {
        return res.data.map((e) => e['id'].toString()).toList();
      }
      
      throw Exception('未知的模型列表格式，请确认接口是否兼容 OpenAI');
    } catch (e) {
      throw Exception('获取模型列表失败，请检查 BaseURL 和 API Key：\n$e');
    }
  }

  // 2. 发送聊天请求 (POST /chat/completions)
  Future<String> chat(List<Map<String, String>> messages) async {
    try {
      String url = config.baseUrl.endsWith('/') 
          ? '${config.baseUrl}chat/completions' 
          : '${config.baseUrl}/chat/completions';
          
      final res = await _dio.post(url, data: {
        'model': config.selectedModelId ?? config.models.first.id, // 默认选第一个
        'messages': messages,
      });
      
      return res.data['choices'][0]['message']['content'] as String;
    } catch (e) {
      throw Exception('请求失败：\n$e');
    }
  }
}