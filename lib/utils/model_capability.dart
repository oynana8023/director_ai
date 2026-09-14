// lib/utils/model_capability.dart
import '../models/llm_config.dart';

class ModelCapabilityResolver {
  /// 根据模型ID自动推断能力
  static LLMModel resolve(String modelId) {
    final id = modelId.toLowerCase();

    // 1. 视频生成（文生视频/图生视频）
    if (id.contains('sora') ||
        id.contains('kling') ||
        id.contains('runway') ||
        id.contains('cogvideo') ||
        id.contains('veo') ||
        id.contains('vidu') ||
        id.contains('video')) {
      return LLMModel(
        id: modelId,
        name: modelId,
        capability: 'video',
        description: '视频生成模型，适合文生视频/图生视频',
      );
    }

    // 2. 图像生成（文生图）
    if (id.contains('dall-e') ||
        id.contains('dalle') ||
        id.contains('cogview') ||
        id.contains('stable-diffusion') ||
        id.contains('flux') ||
        id.contains('midjourney') ||
        id.contains('text2image') ||
        id.contains('image')) {
      return LLMModel(
        id: modelId,
        name: modelId,
        capability: 'image',
        description: '文生图模型，适合插画、海报、概念图生成',
      );
    }

    // 3. 编程/强推理
    if (id.contains('o1') ||
        id.contains('o3') ||
        id.contains('r1') ||
        id.contains('reasoner') ||
        id.contains('coder') ||
        id.contains('codestral') ||
        id.contains('code')) {
      return LLMModel(
        id: modelId,
        name: modelId,
        capability: 'coding',
        description: '强推理/编程模型，适合复杂逻辑与代码生成',
      );
    }

    // 4. 多模态/视觉理解（能看图）
    if (id.contains('vision') ||
        id.contains('vl') ||
        id.contains('gpt-4o') ||
        id.contains('gpt-4-turbo') ||
        id.contains('claude-3') ||
        id.contains('gemini')) {
      return LLMModel(
        id: modelId,
        name: modelId,
        capability: 'multimodal',
        description: '多模态模型，支持图片理解、图文混合问答',
      );
    }

    // 5. 默认：通用聊天
    return LLMModel(
      id: modelId,
      name: modelId,
      capability: 'chat',
      description: '通用对话模型，适合聊天、文案、问答',
    );
  }
}