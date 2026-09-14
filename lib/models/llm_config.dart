// lib/models/llm_config.dart

class LLMModel {
  final String id;          // 模型真实ID，如 "gpt-4o"
  final String name;        // 显示名称
  final String capability;  // 能力分类：chat / coding / image / video / multimodal
  final String description; // 适合做什么的说明

  LLMModel({
    required this.id,
    required this.name,
    required this.capability,
    required this.description,
  });
}

class LLMConfig {
  String id;               // 唯一标识（UUID）
  String name;             // 厂家名称，如 "我的火山云"
  String baseUrl;          // API地址，如 "https://ark.cn-beijing.volces.com/api/v3"
  String apiKey;           // API密钥
  List<LLMModel> models;   // 拉取到的模型列表
  String? selectedModelId; // 当前选中的模型ID

  LLMConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    this.models = const [],
    this.selectedModelId,
  });

  // 转JSON（用于本地存储）
  Map<String, dynamic> toJson() => {
    'id': id, 
    'name': name, 
    'baseUrl': baseUrl, 
    'apiKey': apiKey,
    'selectedModelId': selectedModelId,
    'models': models.map((e) => {
      'id': e.id, 
      'name': e.name, 
      'capability': e.capability, 
      'description': e.description,
    }).toList(),
  };

  // 从JSON解析（用于读取本地存储）
  factory LLMConfig.fromJson(Map<String, dynamic> json) => LLMConfig(
    id: json['id'] ?? '', 
    name: json['name'] ?? '', 
    baseUrl: json['baseUrl'] ?? '',
    apiKey: json['apiKey'] ?? '', 
    selectedModelId: json['selectedModelId'],
    models: (json['models'] as List? ?? []).map((e) => LLMModel(
      id: e['id'] ?? '', 
      name: e['name'] ?? '', 
      capability: e['capability'] ?? 'chat', 
      description: e['description'] ?? '',
    )).toList(),
  );
}