import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

// ==================== 新增动态配置引用 ====================
import 'llm_config_store.dart';
// ========================================================

import '../models/agent_command.dart';
import '../models/character_sheet.dart';
import '../utils/duration_parser.dart';
import '../utils/app_logger.dart';

/// 类型别名：简化 DurationParser 的引用
typedef _DurationParser = DurationParser;
typedef _SceneCountRange = SceneCountRange;

/// GLM 系统提示词 - 剧本规划模式
const String _glmSystemPrompt = '''
You are DirectorAI, a SCREENPLAY CREATION AGENT for short video production.

YOUR MISSION: Convert user's creative idea into a multi-scene screenplay with exactly 3 scenes.
Each scene will be turned into: Narration (Chinese) → Image → Video.

CRITICAL OUTPUT FORMAT:
You MUST respond with ONLY a valid JSON object. No markdown, no explanations, no thinking process.

JSON SCHEMA:
{
  "task_id": "unique_task_id",
  "script_title": "剧本标题",
  "scenes": [
    {
      "scene_id": 1,
      "narration": "中文旁白，描述这一幕的内容",
      "image_prompt": "Detailed English visual description for image generation",
      "video_prompt": "English motion/description for video animation",
      "character_description": "Detailed character description for consistency across scenes",
      "image_url": null,
      "video_url": null,
      "status": "pending"
    }
  ]
}
GUIDELINES:

1. NUMBER OF SCENES: EXACTLY 3 SCENES
   - Scene 1: Introduction / Setup (establish the main character and setting)
   - Scene 2: Development / Action (the main conflict or activity)
   - Scene 3: Resolution / Ending (conclusion and aftermath)
   - Each scene must be focused on ONE key moment

2. CHARACTER CONSISTENCY (CRITICAL):
   - First scene's image_prompt MUST contain detailed character appearance description
   - The character_description field should describe the main character's appearance in detail
   - For subsequent scenes, the image_prompt should reference the same character traits
   - This ensures the same character appears across all scenes

3. NARRATION (Chinese):
   - Short, evocative descriptions
   - 1-2 sentences per scene
   - Sets the mood and context

4. IMAGE_PROMPT (English):
   - Scene 1: Establish the main character with detailed appearance (hair, clothing, face, body type, colors)
   - Scene 2+: Reference the same character using consistent descriptors from scene 1
   - CRITICAL: ALWAYS start with "anime style, manga art, 2D animation, cel shaded"
   - For human characters: specify "Asian" or "Japanese anime style" features
   - AVOID: "realistic, photorealistic, cinematic, 3D render"
   - Example scene 1: "anime style, manga art, 2D animation. A cute orange tabby cat with green eyes and white paws, sitting on grass..."
   - Example scene 2: "anime style, manga art. The same orange tabby cat with green eyes and white paws, now jumping..."

5. VIDEO_PROMPT (English):
   - Motion description: what moves, how, action
   - Keep it consistent with the image

6. CHARACTER_DESCRIPTION (English):
   - A detailed description of the main character's appearance
   - Include: species, colors, distinctive features, clothing, accessories
   - For human characters: specify "anime style, Asian features" or "Japanese anime style"
   - This description will be used to maintain consistency across all scenes

EXAMPLE INPUT: "生成一只猫打架的视频"

EXAMPLE OUTPUT:
{
  "task_id": "cat_fight_20231227",
  "script_title": "猫咪大战",
  "scenes": [
    {
      "scene_id": 1,
      "narration": "两只猫咪在草地上对峙，气氛紧张",
      "image_prompt": "Two cats facing each other on grass, tense standoff. Left: orange tabby cat with bright green eyes and white paws. Right: grey striped cat with amber eyes. Cinematic composition, golden hour lighting, 4k ultra detailed",
      "video_prompt": "Cats circling each other slowly, tails twitching, intense staring",
      "character_description": "Orange tabby cat with bright green eyes, white paws, and striped tail. Grey striped cat with amber eyes and pointed ears.",
      "image_url": null,
      "video_url": null,
      "status": "pending"
    },
    {
      "scene_id": 2,
      "narration": "突然，它们开始激烈地打斗",
      "image_prompt": "The same orange tabby cat with green eyes and white paws fighting the grey striped cat with amber eyes. Mid-action shot, dynamic pose, motion blur, professional sports photography style, dramatic lighting",
      "video_prompt": "Orange cat and grey cat jumping and pouncing, fast dynamic action, paws swiping",
      "character_description": "Orange tabby cat with bright green eyes, white paws, and striped tail. Grey striped cat with amber eyes and pointed ears.",
      "image_url": null,
      "video_url": null,
      "status": "pending"
    },
    {
      "scene_id": 3,
      "narration": "打斗结束，各自离开",
      "image_prompt": "The orange tabby cat with green eyes and white paws walking left, away from camera. The grey striped cat with amber eyes walking right. Calm aftermath, sunset lighting, peaceful atmosphere, 4k detailed",
      "video_prompt": "Orange cat and grey cat calmly walking away from each other in opposite directions, slow movement",
      "character_description": "Orange tabby cat with bright green eyes, white paws, and striped tail. Grey striped cat with amber eyes and pointed ears.",
      "image_url": null,
      "video_url": null,
      "status": "pending"
    }
  ]
}

ABSOLUTE RULES:
1. Output ONLY valid JSON - no markdown code blocks, no explanations
2. scene_id must be sequential starting from 1
3. ALWAYS include exactly 3 scenes (no more, no less)
4. All scenes must have the SAME character_description value
5. Scene 1's image_prompt establishes character appearance
6. Scenes 2 and 3 must reference the same character appearance in image_prompt
7. CRITICAL: EVERY image_prompt MUST start with "anime style, manga art, 2D animation"
8. CRITICAL: For human characters, specify "Asian" or "Japanese anime style" features
9. CRITICAL: NEVER use "realistic, photorealistic, cinematic, 3D render" in prompts
10. image_url and video_url must be null initially
11. status must be "pending" for all scenes
12. Generate a unique task_id using format: task_[timestamp]_[topic]
''';

/// GLM 系统提示词 - 普通聊天模式
const String _glmChatPrompt = '''
You are AI漫导 (DirectorAI), a friendly AI assistant specialized in video content creation.

你的职责：
1. 友好地与用户交流
2. 了解用户想要创作什么样的视频
3. 当用户明确表示要生成视频时，引导他们提供具体的创意描述

回复风格：
- 友好、专业、简洁
- 使用中文回复
- 可以使用表情符号增加亲和力
- 当用户只是打招呼时，简要介绍你的功能
- 当用户提到想制作视频时，询问具体的创意内容（角色、场景、风格等）

示例：
用户：你好
你：你好！我是 AI 漫导 🎬 我可以帮你创作各种视频内容，比如动画、短片、风景视频等。你想创作什么样的视频呢？

用户：我想做个视频
你：太好了！请告诉我更多细节吧，比如：
- 视频里有什么角色或场景？
- 想要什么风格（可爱、酷炫、温馨等）？
- 大概想要什么样的故事情节？

请自然地与用户对话，引导他们提供足够的创意信息。
''';

/// GLM 系统提示词 - 漫剧剧本生成模式
const String _dramaSystemPrompt = '''
You are DirectorAI, a PROFESSIONAL SCREENPLAY WRITER for manga-style drama videos.

YOUR MISSION: Create a compelling 1-minute drama screenplay with emotional hooks,
plot twists, and engaging narrative structure.

REQUIREMENTS:
1. LENGTH: 6-8 scenes (approximately 60-90 seconds total)
2. EMOTIONAL HOOK: Each scene should build positive emotional connection
3. PLOT TWIST: Include heartwarming or surprising moments (NOT tragic or dark)
4. GENRE: POSITIVE manga-style stories ONLY:
   - Campus life / School days
   - Friendship and bonding
   - Youth and dreams
   - Sweet romance
   - Healing / Comforting stories
   - Daily life warmth
   - AVOID: revenge, violence, horror, tragedy, crime, suspense with threats

STRUCTURE:
- Opening (1-2 scenes): Establish setting and characters in a positive light
- Development (2-3 scenes): Build warm connections or gentle challenges
- Heartwarming Moment (1-2 scenes): Emotional peak - touching, sweet, or inspiring
- Resolution (1-2 scenes): Happy or hopeful conclusion

CRITICAL OUTPUT FORMAT:
You MUST respond with ONLY a valid JSON object.
- NO markdown code blocks (```json ... ```)
- NO explanations before or after the JSON
- NO comments in the JSON
- Use ONLY standard English double quotes " " for all strings
- NEVER use Chinese quotes " " or ''
- Ensure all brackets { } [ ] are properly matched
- All string values must be wrapped in double quotes
- Do NOT use trailing commas

JSON SCHEMA:
{
  "task_id": "unique_id",
  "title": "剧本标题",
  "genre": "类型 (浪漫/悬疑/复仇/成长等)",
  "estimated_duration_seconds": 60,
  "emotional_arc": ["情绪变化描述", "如: 紧张→困惑→震惊→感动"],
  "scenes": [
    {
      "scene_id": 1,
      "narration": "中文旁白，富有感染力，营造氛围",
      "mood": "情绪标签 (紧张/温馨/悲伤/愤怒/惊喜/浪漫等)",
      "emotional_hook": "本场景的情绪钩子，如何吸引观众注意力",
      "image_prompt": "英文图片生成提示词，详细描述视觉画面",
      "video_prompt": "英文视频动效提示词，描述镜头运动和人物动作",
      "character_description": "人物特征描述，用于保持一致性"
    }
  ]
}

GUIDELINES:

1. SCENE COUNT: 6-8 SCENES TOTAL
   - Each scene represents a key story beat
   - Each scene should be 8-15 seconds when realized as video

2. EMOTIONAL HOOKS:
   - Start with intrigue or mystery
   - Use contrast between expectation and reality
   - Create moments of revelation
   - End with emotional resonance

3. PLOT TWIST TECHNIQUES:
   - False assumptions revealed
   - Hidden motivations uncovered
   - Unexpected alliances or betrayals
   - Role reversals
   - Time reveals truth

4. NARRATION (Chinese):
   - Evocative, emotionally resonant
   - 2-3 sentences per scene
   - Build atmosphere and tension
   - Use dialogue-like quality for immersion

5. MOOD LABELS:
   Choose from: 温馨, 愉快, 惊喜, 浪漫, 期待, 感动, 治愈, 宁静, 活泼, 甜蜜
   AVOID: 紧张, 悲伤, 愤怒, 绝望, 恐惧 - these may trigger content filters

6. EMOTIONAL_HOOK:
   - Brief phrase explaining the POSITIVE emotional moment
   - What warm feeling the audience should experience
   - How this scene builds emotional connection
   - Focus on: heartwarming, sweet, touching, inspiring moments

7. IMAGE_PROMPT (English):
   - Scene 1: Establish main character with detailed appearance
   - All scenes: Use consistent character descriptions
   - Include mood-appropriate lighting and composition
   - CRITICAL: ALWAYS include anime/manga style keywords at the START: "anime style, manga art, 2D animation, cel shaded"
   - Additional style keywords: "Japanese anime style, manhwa, webtoon art, vibrant colors, clean lines"
   - AVOID: "realistic, photorealistic, cinematic, 3D render" - these create realistic western-style images

8. VIDEO_PROMPT (English):
   CRITICAL: MUST start with camera type and movement, then character action
   FORMAT: "[Camera Type] + [Camera Movement] + [Character Action with Dialogue]"

   Camera TYPES - choose based on scene mood:
   - Close-up (特写): Emotions, dialogue, reactions - "Close-up shot of face"
   - Medium Shot (中景): Upper body, interactions - "Medium shot showing upper body"
   - Wide Shot (广角): Environment, establishing scene - "Wide shot showing full scene"
   - Over-the-Shoulder (过肩): Conversations between characters - "Over-the-shoulder shot from A looking at B"
   - Two-Shot (双人镜头): Two characters together - "Two-shot showing both characters"
   - Low Angle (仰拍): Character looks powerful/heroic - "Low angle shot looking up at character"
   - High Angle (俯拍): Character looks vulnerable/alone - "High angle shot looking down"
   - POV Shot (主观视角): Seeing through character's eyes - "POV shot from character's view"
   - Profile Shot (侧拍): Side view of character - "Profile shot showing character's face"
   - Dutch Angle (倾斜镜头): Tension, unease - "Dutch angle for uneasy feeling" (USE SPARINGLY)

   Camera MOVEMENTS:
   - Static/Fixed (固定): No movement, focus on action - "Static camera, focus on..."
   - Pan (摇拍): Side to side - "Slow pan left to reveal...", "Pan right following..."
   - Tilt (俯仰拍): Up/down - "Tilt up to reveal face", "Tilt down showing..."
   - Dolly/Tracking (跟拍): Follow character - "Tracking shot following character...", "Dolly in toward..."
   - Push In (推进): Emphasize emotion - "Slow push in on face to show emotion"
   - Pull Back (拉远): Reveal context - "Pull back to reveal full scene"
   - Zoom (变焦): Quick attention - "Quick zoom on..." (USE SPARINGLY)

   Scene-Specific Recommendations:
   - EMOTIONAL/QUIET moments: Static or Slow movement + Close-up
   - REVEAL/SURPRISE moments: Quick pan or Push in + Medium/Wide
   - DIALOGUE/CONVERSATION: Over-the-shoulder or Two-shot + Static/Slight movement
   - ACTION/MOVEMENT: Tracking shot or Following shot
   - ENVIRONMENT/ESTABLISHING: Wide shot + Pan
   - INTIMATE/ROMANTIC: Close-up + Slow push in
   - TENSION/SUSPENSE: Static or Slight zoom + Close-up

   CRITICAL: Character must SPEAK in Chinese - add "character speaking, talking, mouth moving, saying dialogue" to EVERY video
   Include dialogue in the action: "girl saying '你好' with warm smile", "boy talking '谢谢'"
   Lip sync and facial expressions should match the speech

   CRITICAL: Voice gender MUST match character gender - add voice specification to EVERY video_prompt:
   - For male characters: "male voice, man speaking, masculine voice"
   - For female characters: "female voice, woman speaking, feminine voice"
   - Examples: "girl says '你好' with female voice", "boy speaks '谢谢' with male voice"
   - Keep voice consistent across ALL scenes for the SAME character

   CRITICAL SAFETY GUIDELINES - MUST FOLLOW TO PASS CONTENT FILTERING:

   *** ABSOLUTELY FORBIDDEN WORDS (will trigger platform rejection): ***
   - Energy/Effects: lightning, electric, electric shock, thunderbolt, energy, energy beam, energy surge, power surge, spark, arc, voltage
   - Combat/Fighting: attack, battle, fight, punch, kick, hit, strike, slam, crash, smash, beat, combat, clash, confront, struggle
   - Dangerous Elements: fire, flame, burn, explosion, explode, blast, bomb, smoke, weapon, sword, knife, gun, blade, sharp, pointed
   - Negative Emotions: fierce, intense, aggressive, violent, rage, angry, furious, terrified, horrified, scream, shout, yell, panic
   - Body Horror: glowing eyes, red eyes, blood, wound, injury, transform, mutate, distort, twisted
   - Unsafe Actions: fall, drop, trip, stumble, chase, flee, escape, running scared

   *** MANDATORY SAFE ALTERNATIVES: ***
   - Instead of "lightning/electric": soft light, gentle light, warm light, ambient light, natural light, sunlight, glow
   - Instead of "fight/attack": move toward, approach, interaction, encounter, meet, face each other
   - Instead of "fierce/intense": warm, calm, gentle, peaceful, quiet, soft, smooth, elegant, graceful
   - Instead of "explosion/fire": bloom, flourish, brighten, illuminate, radiate, shimmer
   - Instead of "angry/rage": concerned, worried, surprised, amazed, excited, eager, focused
   - Instead of "scream/shout": speak, say, whisper, call out, reply, respond

   *** REQUIRED SAFE WORDS TO INCLUDE: ***
   Must use at least 2 of these in EACH video_prompt:
   - gentle, soft, calm, peaceful, warm, bright, smooth, quiet, serene, tranquil
   - beautiful, lovely, cute, sweet, heartwarming, pleasant, comfortable
   - slowly, softly, gently, calmly, smoothly, gracefully, elegantly

   *** SAFE CAMERA MOVEMENTS ONLY: ***
   - ALWAYS use: slow, gentle, soft, smooth, calm
   - NEVER use: quick, fast, sudden, rapid, sharp, abrupt, violent, jerky
   - Safe examples: "slowly", "gently", "smoothly", "calmly", "softly"

9. CHARACTER_DESCRIPTION (English):
   - Detailed appearance for consistency
   - Include: species/hair/color/features/clothing
   - Used across ALL scenes
   - CRITICAL: Always specify "anime style, Asian features" for human characters
   - Default to Japanese/Asian appearance unless user specifies otherwise

EXAMPLE INPUT: "生成一个关于校园友谊的温馨视频"

EXAMPLE OUTPUT:
{
  "task_id": "school_friendship_20240127",
  "title": "同桌的你",
  "genre": "校园友情",
  "estimated_duration_seconds": 60,
  "emotional_arc": ["宁静", "期待", "惊喜", "感动", "温馨"],
  "scenes": [
    {
      "scene_id": 1,
      "narration": "午后的教室，阳光洒在课桌上，女孩正在认真做笔记",
      "mood": "宁静",
      "emotional_hook": "校园午后的静谧时光",
      "image_prompt": "anime style, manga art, 2D animation, cel shaded. A bright Japanese high school classroom with sunlight streaming through windows. A teenage Asian girl with short black hair and gentle eyes sitting at a desk, writing notes calmly. Warm golden hour lighting, peaceful atmosphere, clean anime art style",
      "video_prompt": "Anime style 2D animation. Static camera with Medium shot showing girl at desk studying. Girl looks up, smiles at window, and says to herself '今天天气真好' with peaceful expression, female voice",
      "character_description": "Anime style Asian girl, 16 years old, short black bob hair, dark gentle eyes, wearing Japanese high school uniform with white shirt and navy skirt"
    },
    {
      "scene_id": 2,
      "narration": "旁边的座位空着，那是她同桌的位置，已经三天没来了",
      "mood": "期待",
      "emotional_hook": "关心朋友：她还好吗？",
      "image_prompt": "anime style, manga art, 2D animation, cel shaded. The same Asian girl glancing at the empty desk next to hers with a slightly worried expression. A bento box wrapped in cloth sits on her desk. Soft lighting, Japanese classroom setting, heartwarming anime art style",
      "video_prompt": "Anime style 2D animation. Close-up static shot of girl's worried face glancing at empty desk. Girl whispers '不知道她怎么样了' with concerned expression, female voice",
      "character_description": "Anime style Asian girl, 16 years old, short black bob hair, dark gentle eyes, wearing Japanese high school uniform"
    },
    {
      "scene_id": 3,
      "narration": "门口突然出现熟悉的身影，女孩惊喜地站起来",
      "mood": "惊喜",
      "emotional_hook": "朋友回来了！",
      "image_prompt": "anime style, manga art, 2D animation, cel shaded. Another Asian girl with long ponytail standing at the classroom door, smiling warmly. The girl at the desk is looking up with happy surprise, starting to stand up. Bright anime art style, warm colors",
      "video_prompt": "Anime style 2D animation. Quick pan right from girl's desk to doorway, revealing friend standing there. Girl's eyes light up, she stands up and calls out '你回来啦！' with excited smile, female voice",
      "character_description": "Anime style Asian girl, 16 years old, short black bob hair, dark gentle eyes, wearing Japanese high school uniform. Another Asian girl, 16 years old, long black ponytail, warm smile, wearing matching school uniform"
    },
    {
      "scene_id": 4,
      "narration": "朋友走到她身边，轻轻递过一个小盒子：谢谢你这几天的笔记",
      "mood": "感动",
      "emotional_hook": "被记挂的温暖",
      "image_prompt": "anime style, manga art, 2D animation, cel shaded. The ponytail girl handing a small wrapped gift to the bob-haired girl, who is smiling with touched emotion. The bento box on the desk is now revealed to be for the friend. Warm afternoon light, heartwarming composition, Japanese anime art style",
      "video_prompt": "Anime style 2D animation. Two-shot static camera showing both girls at adjacent desks. Ponytail girl hands over gift and says '谢谢你帮我记笔记' with sincere smile, female voice. Bob-haired girl receives gift with touched expression",
      "character_description": "Anime style Asian girl, 16 years old, short black bob hair, dark gentle eyes, wearing Japanese high school uniform. Another Asian girl, 16 years old, long black ponytail, warm smile, wearing matching school uniform"
    },
    {
      "scene_id": 5,
      "narration": "原来她生病了，但还记得把自己做的便当送来",
      "mood": "温馨",
      "emotional_hook": "双向奔赴的友情",
      "image_prompt": "anime style, manga art, 2D animation, cel shaded. Both Asian girls sitting together at adjacent desks, sharing the bento box and laughing. Sunlight creates a warm glow around them. Happy friendship moment, Japanese anime art style, vibrant and cheerful colors",
      "video_prompt": "Anime style 2D animation. Medium shot from side showing both girls eating together. Girl takes a bite, smiles and says '这个好吃！' with female voice. They laugh together. Warm, happy atmosphere",
      "character_description": "Anime style Asian girl, 16 years old, short black bob hair, dark gentle eyes, wearing Japanese high school uniform. Another Asian girl, 16 years old, long black ponytail, warm smile, wearing matching school uniform"
    },
    {
      "scene_id": 6,
      "narration": "放学铃声响起，两人相视一笑，一起收拾书包走出教室",
      "mood": "甜蜜",
      "emotional_hook": "有朋友真好",
      "image_prompt": "anime style, manga art, 2D animation, cel shaded. Both Asian girls walking side by side toward the classroom door, carrying their school bags. Orange sunset light streaming through windows creates a golden glow. School ending atmosphere, sweet friendship moment, Japanese anime art style",
      "video_prompt": "Anime style 2D animation. Tracking shot following from behind as both girls walk toward door. They exchange looks, one says '明天见！' with female voice and other replies '明天见！' with female voice while waving. Camera shows their backs exiting into sunset",
      "character_description": "Anime style Asian girl, 16 years old, short black bob hair, dark gentle eyes, wearing Japanese high school uniform. Another Asian girl, 16 years old, long black ponytail, warm smile, wearing matching school uniform"
    }
  ]
}

ABSOLUTE RULES:
1. CRITICAL: Output ONLY valid JSON - no markdown code blocks, no explanations
   - MUST use English double quotes " " NOT Chinese quotes " "
   - All strings must be quoted
   - No trailing commas
   - Proper bracket matching
2. 6-8 scenes exactly
3. All scenes must have consistent character descriptions
4. Each scene must have a unique mood that progresses the emotional arc
5. Include at least one heartwarming or touching moment
6. Keep everything POSITIVE - no tragedy, violence, horror, or dark themes
7. CRITICAL: EVERY image_prompt MUST start with "anime style, manga art, 2D animation, cel shaded"
8. CRITICAL: All human characters MUST be described as "Asian" or "Japanese anime style"
9. CRITICAL: NEVER use words like "realistic", "photorealistic", "cinematic", "3D render"
10. CRITICAL: NEVER use negative words in video_prompt: no lightning, fierce, intense, dramatic, aggressive
11. ALWAYS use gentle words: soft, calm, warm, bright, smooth, peaceful, gentle
12. CRITICAL: EVERY video_prompt MUST follow format: "[Camera Type] + [Movement] + [Action with Chinese dialogue]"
13. CRITICAL: EVERY video_prompt MUST specify camera type: Close-up, Medium Shot, Wide Shot, Two-Shot, Over-the-shoulder, Tracking, etc.
14. CRITICAL: EVERY video_prompt MUST include character speaking in Chinese with matching voice gender (male voice for men, female voice for women)
15. VARY camera types across scenes - don't use the same shot for every scene
16. CRITICAL: Keep VOICE GENDER CONSISTENT - same character must use same voice gender in ALL scenes
17. Generate unique task_id: drama_[timestamp]_[theme]
''';

/// GLM 流式响应数据类型
enum GLMStreamType {
  thinking,  // 思考过程 (reasoning_content)
  content,   // 最终内容 (content)
}

/// GLM 流式响应块
class GLMStreamChunk {
  final GLMStreamType type;
  final String text;

  GLMStreamChunk({required this.type, required this.text});

  bool get isThinking => type == GLMStreamType.thinking;
  bool get isContent => type == GLMStreamType.content;
}

// ==================== 动态配置的 ApiConfig ====================
/// API 配置
class ApiConfig {
  // ==================== 功能开关 ====================
  static const bool USE_MOCK_VIDEO_API = false;
  static const bool USE_MOCK_IMAGE_API = false;
  static const bool USE_MOCK_CHARACTER_SHEET_API = false;
  static const bool USE_THINKING_MODE = true;

  // ==================== 场景配置 ====================
  static int sceneCount = 7;
  static int concurrentScenes = 2;

  // ==================== Mock URL ====================
  static const String MOCK_VIDEO_URL = 'https://www.w3schools.com/html/mov_bbb.mp4';
  static const String MOCK_IMAGE_URL = 'https://pro.filesystem.site/cdn/20251231/068472ac4cc0ac7a4a8bdb3dcfb693.jpeg';
  static const String MOCK_CHARACTER_COMBINED_URL = 'https://pro.filesystem.site/cdn/20251231/068472ac4cc0ac7a4a8bdb3dcfb693.jpeg';

  // ==================== 动态获取配置 ====================
  /// 获取指定用途的 Dio 实例，如果未绑定则抛出异常
  static Future<Dio> getRequiredDio(String usage) async {
    final config = await LLMConfigStore().getActiveConfig(usage);
    if (config == null || config.baseUrl.isEmpty) {
      throw Exception('请先去设置页面绑定【$usage】模型');
    }
    return Dio(BaseOptions(
      baseUrl: config.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${config.apiKey}',
      },
    ));
  }

  /// 获取指定用途的模型名称，如果未选择则抛出异常
  static Future<String> getRequiredModel(String usage) async {
    final config = await LLMConfigStore().getActiveConfig(usage);
    if (config == null || config.selectedModelId == null || config.selectedModelId!.isEmpty) {
      throw Exception('请先去设置页面选择【$usage】模型');
    }
    return config.selectedModelId!;
  }

  // 兼容旧代码（标记为已弃用，防止原文件其他地方报错）
  @Deprecated('使用 LLMConfigStore 替代')
  static String get zhipuApiKey => '';
  @Deprecated('使用 LLMConfigStore 替代')
  static String get videoApiKey => '';
  @Deprecated('使用 LLMConfigStore 替代')
  static String get imageApiKey => '';
  @Deprecated('使用 LLMConfigStore 替代')
  static String get doubaoApiKey => '';
}

// ==================== 动态路由请求的 ApiService ====================
/// 处理所有 API 调用的服务类（动态配置版）
class ApiService {

  // ==================== GLM 智能体 API（动态对话模型） ====================

  /// 普通聊天方法
  Stream<GLMStreamChunk> chatWithGLM(List<Map<String, String>> conversationHistory) async* {
    yield* sendToGLMStream(conversationHistory, systemPrompt: _glmChatPrompt);
  }

  /// 支持图片识别的聊天方法
  Stream<GLMStreamChunk> chatWithGLMImageSupport({
    required String userMessage,
    String? imageBase64,
    String? imageMimeType,
    List<Map<String, String>> conversationHistory = const [],
  }) async* {
    try {
      final hasImage = imageBase64 != null && imageBase64.isNotEmpty;

      if (hasImage) {
        // === 图片模式：使用 "vision" 绑定的模型 ===
        final dio = await ApiConfig.getRequiredDio('vision');
        final model = await ApiConfig.getRequiredModel('vision');
        final mimeType = imageMimeType ?? 'image/jpeg';

        final requestData = {
          'model': model,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'image_url', 'image_url': {'url': 'data:$mimeType;base64,$imageBase64'}},
                {'type': 'text', 'text': userMessage},
              ],
            },
          ],
        };

        AppLogger.info('动态视觉模型', '使用模型: $model');
        final response = await dio.post('/chat/completions', data: requestData);
        final content = response.data['choices']?[0]?['message']?['content'] as String?;

        if (content != null && content.isNotEmpty) {
          yield GLMStreamChunk(type: GLMStreamType.content, text: content);
        } else {
          throw Exception('响应格式错误：content 为空');
        }
      } else {
        // === 纯文本模式：使用 "chat" 绑定的模型 ===
        final dio = await ApiConfig.getRequiredDio('chat');
        final model = await ApiConfig.getRequiredModel('chat');

        final messages = <Map<String, dynamic>>[
          {'role': 'system', 'content': _glmChatPrompt},
          ...conversationHistory,
          {'role': 'user', 'content': userMessage},
        ];

        final requestData = <String, dynamic>{
          'model': model,
          'messages': messages,
          'stream': true,
          'max_tokens': 65536,
          'temperature': 1.0,
        };

        if (ApiConfig.USE_THINKING_MODE) {
          requestData['thinking'] = {'type': 'enabled'};
        }

        AppLogger.info('动态对话模型', '使用模型: $model');
        final response = await dio.post<ResponseBody>(
          '/chat/completions',
          data: requestData,
          options: Options(responseType: ResponseType.stream),
        );

        final contentBuffer = StringBuffer();
        final thinkingBuffer = StringBuffer();
        String incompleteLine = '';

        await for (final chunk in response.data!.stream) {
          final chunkStr = utf8.decode(chunk, allowMalformed: true);
          final fullData = incompleteLine + chunkStr;
          final lines = fullData.split('\n');
          incompleteLine = lines.removeLast();

          for (final line in lines) {
            if (line.trim().isEmpty) continue;
            if (line.startsWith('data: ')) {
              final data = line.substring(6);
              if (data.trim() == '[DONE]') return;
              try {
                final json = jsonDecode(data);
                final delta = json['choices']?[0]?['delta'];
                if (delta == null) continue;

                final reasoningContent = delta['reasoning_content'] as String?;
                final content = delta['content'] as String?;

                if (reasoningContent != null && reasoningContent.isNotEmpty) {
                  thinkingBuffer.write(reasoningContent);
                  yield GLMStreamChunk(type: GLMStreamType.thinking, text: reasoningContent);
                }
                if (content != null && content.isNotEmpty) {
                  contentBuffer.write(content);
                  yield GLMStreamChunk(type: GLMStreamType.content, text: content);
                }
              } catch (_) {}
            }
          }
        }
        if (contentBuffer.isEmpty && thinkingBuffer.isEmpty) {
          yield GLMStreamChunk(type: GLMStreamType.content, text: '');
        }
      }
    } catch (e) {
      AppLogger.error('聊天', 'API 调用失败', e, StackTrace.current);
      throw Exception('聊天错误: $e');
    }
  }

  /// 非流式对话（剧本生成等）
  Future<String> sendToGLM(List<Map<String, String>> conversationHistory) async {
    try {
      final dio = await ApiConfig.getRequiredDio('chat');
      final model = await ApiConfig.getRequiredModel('chat');

      final messages = [
        {'role': 'system', 'content': _glmSystemPrompt},
        ...conversationHistory,
      ];

      final requestData = {
        'model': model,
        'messages': messages,
        'stream': false,
        'max_tokens': 65536,
        'temperature': 1.0,
      };

      final response = await dio.post('/chat/completions', data: requestData);
      final content = response.data['choices']?[0]?['message']?['content'] as String?;
      if (content == null) throw Exception('响应中没有内容');
      return content;
    } catch (e) {
      throw Exception('API 错误: $e');
    }
  }

  /// 流式对话（带思考过程）
  Stream<GLMStreamChunk> sendToGLMStream(
    List<Map<String, dynamic>> conversationHistory, {
    String? systemPrompt,
  }) async* {
    try {
      final dio = await ApiConfig.getRequiredDio('chat');
      final model = await ApiConfig.getRequiredModel('chat');
      final prompt = systemPrompt ?? _glmSystemPrompt;

      final messages = [
        {'role': 'system', 'content': prompt},
        ...conversationHistory,
      ];

      final requestData = <String, dynamic>{
        'model': model,
        'messages': messages,
        'stream': true,
        'max_tokens': 65536,
        'temperature': 1.0,
      };

      if (ApiConfig.USE_THINKING_MODE) {
        requestData['thinking'] = {'type': 'enabled'};
      }

      final response = await dio.post<ResponseBody>(
        '/chat/completions',
        data: requestData,
        options: Options(responseType: ResponseType.stream),
      );

      final contentBuffer = StringBuffer();
      final thinkingBuffer = StringBuffer();
      String incompleteLine = '';

      await for (final chunk in response.data!.stream) {
        final chunkStr = utf8.decode(chunk, allowMalformed: true);
        final fullData = incompleteLine + chunkStr;
        final lines = fullData.split('\n');
        incompleteLine = lines.removeLast();

        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data.trim() == '[DONE]') return;
            try {
              final json = jsonDecode(data);
              final delta = json['choices']?[0]?['delta'];
              if (delta == null) continue;

              final reasoningContent = delta['reasoning_content'] as String?;
              final content = delta['content'] as String?;

              if (reasoningContent != null && reasoningContent.isNotEmpty) {
                thinkingBuffer.write(reasoningContent);
                yield GLMStreamChunk(type: GLMStreamType.thinking, text: reasoningContent);
              }
              if (content != null && content.isNotEmpty) {
                contentBuffer.write(content);
                yield GLMStreamChunk(type: GLMStreamType.content, text: content);
              }
            } catch (_) {}
          }
        }
      }
      if (contentBuffer.isEmpty && thinkingBuffer.isEmpty) {
        yield GLMStreamChunk(type: GLMStreamType.content, text: '');
      }
    } catch (e) {
      throw Exception('API 流式错误: $e');
    }
  }

  // ==================== 漫剧剧本生成（动态对话模型） ====================
  Future<String> generateDramaScreenplay(
    String userPrompt, {
    String? characterAnalysis,
    String? previousFeedback,
  }) async {
    const maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final configuredSceneCount = ApiConfig.sceneCount;
        String enhancedPrompt = userPrompt;

        if (characterAnalysis != null && characterAnalysis.isNotEmpty) {
          enhancedPrompt = '用户需求：$enhancedPrompt\n\n用户提供的参考图片角色特征分析：\n$characterAnalysis\n\n请根据上述角色特征分析结果，生成剧本中的 character_description 字段，确保生成的角色形象与用户提供的图片一致。';
        }
        if (previousFeedback != null && previousFeedback.isNotEmpty) {
          enhancedPrompt = '$enhancedPrompt\n\n用户对上一版剧本的反馈：\n$previousFeedback\n\n请根据用户反馈调整剧本，生成更好的版本。';
        }
        if (attempt > 1) {
          enhancedPrompt = '$enhancedPrompt\n\n重要提醒：上次生成的 JSON 格式有误，请确保：1. 输出纯 JSON 格式。2. 使用标准英文双引号。3. 所有字符串必须用引号包裹。4. 确保括号正确配对。';
        }

        final dynamicSystemPrompt = _buildDynamicDramaPromptWithCount(configuredSceneCount);
        final contentBuffer = StringBuffer();

        await for (final chunk in sendToGLMStream(
          [{'role': 'user', 'content': enhancedPrompt}],
          systemPrompt: dynamicSystemPrompt,
        )) {
          if (chunk.isContent) contentBuffer.write(chunk.text);
        }

        String responseJson = contentBuffer.toString()
            .replaceAll('“', '"').replaceAll('”', '"')
            .replaceAll('‘', '\'').replaceAll('’', '\'')
            .replaceAll('：', ':')
            .replaceAll(RegExp(r'```json\s*'), '').replaceAll(RegExp(r'```\s*'), '').trim();

        try {
          final decoded = jsonDecode(responseJson);
          if (!decoded.containsKey('task_id') || !decoded.containsKey('title') || !decoded.containsKey('scenes')) {
            throw FormatException('缺少必需字段');
          }
          final scenes = decoded['scenes'] as List?;
          if (scenes == null || scenes.isEmpty) throw FormatException('场景数量不足');
          return responseJson;
        } on FormatException catch (e) {
          if (attempt == maxRetries) throw Exception('JSON 格式验证失败: $e\n响应内容: $responseJson');
          continue;
        }
      } catch (e) {
        if (attempt == maxRetries) throw Exception('漫剧剧本生成失败: $e');
        continue;
      }
    }
    throw Exception('漫剧剧本生成失败：超过最大重试次数');
  }

  String _buildDynamicDramaPromptWithCount(int sceneCount) {
    String prompt = _dramaSystemPrompt.replaceAll(
      RegExp(r'1\. LENGTH: 6-8 scenes \(approximately 60-90 seconds total\)'),
      '1. LENGTH: EXACTLY $sceneCount SCENES (each scene 5-10 seconds)',
    );
    prompt = prompt.replaceAll(RegExp(r'1\. 6-8 scenes exactly'), '1. EXACTLY $sceneCount scenes');
    prompt = prompt.replaceAll('ABSOLUTE RULES:', 'ABSOLUTE RULES:\n0. CRITICAL: You MUST generate EXACTLY $sceneCount scenes. No more, no less.');
    return prompt;
  }

  // ==================== 图像分析（动态 vision 模型） ====================
  Future<String> analyzeImageForCharacter(String imageBase64, {String mimeType = 'image/jpeg'}) async {
    try {
      final dio = await ApiConfig.getRequiredDio('vision');
      final model = await ApiConfig.getRequiredModel('vision');

      const prompt = '请仔细观察这张图片，提取其中主要角色或人物的详细特征描述。\n\n请按照以下格式返回（只返回描述，不要其他内容）：\n\n**外观特征**：[详细描述角色外观]\n**穿着打扮**：[描述服装风格]\n**姿态表情**：[描述姿态表情]\n**整体风格**：[一句话总结]';

      final requestData = {
        'model': model,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'image_url', 'image_url': {'url': 'data:$mimeType;base64,$imageBase64'}},
              {'type': 'text', 'text': prompt},
            ],
          },
        ],
      };

      final response = await dio.post('/chat/completions', data: requestData);
      final content = response.data['choices']?[0]?['message']?['content'] as String?;
      if (content == null || content.isEmpty) throw Exception('图片分析失败：响应为空');
      return content;
    } catch (e) {
      throw Exception('图片分析失败: $e');
    }
  }

  // ==================== 图像生成（动态 image 模型） ====================
  Future<String> generateImage(String prompt, {List<String>? referenceImages}) async {
    if (ApiConfig.USE_MOCK_IMAGE_API) return ApiConfig.MOCK_IMAGE_URL;
    return _generateImageWithRetry(prompt, referenceImages: referenceImages);
  }

  Future<String> _generateImageWithRetry(String prompt, {List<String>? referenceImages, int retryCount = 0}) async {
    try {
      final dio = await ApiConfig.getRequiredDio('image');
      final model = await ApiConfig.getRequiredModel('image');

      final requestData = {
        'model': model,
        'prompt': prompt,
        'n': 1,
        'response_format': 'url',
        'size': '1024x1024',
      };
      if (referenceImages != null && referenceImages.isNotEmpty) {
        requestData['image'] = referenceImages;
      }

      final response = await dio.post('/v1/images/generations', data: requestData);
      final dataList = response.data['data'] as List?;
      if (dataList == null || dataList.isEmpty) throw Exception('响应中没有 data 数组');
      final imageUrl = dataList[0]['url'] as String?;
      if (imageUrl == null || imageUrl.isEmpty) throw Exception('响应中 URL 为空');
      return imageUrl;
    } catch (e) {
      if (e is DioException && e.response?.data is Map) {
        final message = e.response?.data['message']?.toString() ?? '';
        if ((message.contains('PUBLIC_ERROR_UNSAFE_GENERATION') || message.contains('generation_failed')) && retryCount == 0) {
          return _generateImageWithRetry(_sanitizePrompt(prompt), referenceImages: referenceImages, retryCount: 1);
        }
      }
      throw Exception('图片生成错误: $e');
    }
  }

  String _sanitizePrompt(String prompt) {
    return prompt
        .replaceAll(RegExp(r'\b(sexy|nude|naked|breast|underwear|lingerie|intimate|suggestive)\b', caseSensitive: false), 'beautiful')
        .replaceAll(RegExp(r'\b(violence|blood|kill|death|weapon|gore)\b', caseSensitive: false), 'dramatic')
        .replaceAll(RegExp(r'\b(disturbing|shocking|offensive)\b', caseSensitive: false), 'artistic')
        .replaceAll(RegExp(r'\b(highly detailed|extreme|intense|realistic skin|anatomically correct)\b', caseSensitive: false), 'detailed')
        .trim() + ', professional photography, high quality, cinematic lighting';
  }

  String _sanitizeVideoPrompt(String prompt) {
    String sanitized = prompt;
    final violentPatterns = [r'lightning\s+effects?', r'glowing\s+(eyes|hands|body)', r'electric\s+\w+', r'energy\s+swirl', r'powerful?\s+\w+', r'explosion', r'fire\s+\w+', r'violent?\s+\w+', r'attack\s+\w+', r'battle\s+\w+', r'fight\s+\w+', r'weapon', r'danger', r'threaten', r'aggressive', r'intense', r'dramatic\s+lightning', r'fierce'];
    for (final pattern in violentPatterns) {
      sanitized = sanitized.replaceAll(RegExp(pattern, caseSensitive: false), 'gentle');
    }
    final replacements = {'lightning': 'soft light', 'glowing': 'bright', 'energy': 'atmosphere', 'swirl': 'flow', 'powerful': 'beautiful', 'strong': 'elegant', 'fierce': 'calm', 'intense': 'warm', 'dramatic': 'peaceful', 'action': 'scene', 'dynamic': 'smooth'};
    for (final entry in replacements.entries) {
      sanitized = sanitized.replaceAll(RegExp(entry.key, caseSensitive: false), entry.value);
    }
    return 'Peaceful anime style scene. $sanitized. Calm and positive atmosphere.';
  }

  Future<String> rewriteVideoPromptForSafety({required String originalPrompt, required String sceneNarration}) async {
    try {
      final dio = await ApiConfig.getRequiredDio('chat');
      final model = await ApiConfig.getRequiredModel('chat');
      final rewritePrompt = '将以下视频提示词重写为100%安全的表达，避免所有暴力、能量、负面情绪词汇。50词以内。\n原始: $originalPrompt\n旁白: $sceneNarration\n直接输出重写后的英文提示词。';
      
      final response = await dio.post('/chat/completions', data: {
        'model': model,
        'messages': [{'role': 'user', 'content': rewritePrompt}],
        'temperature': 0.7,
      });
      final rewritten = response.data['choices']?[0]?['message']?['content'] as String?;
      return rewritten?.trim() ?? _sanitizeVideoPrompt(originalPrompt);
    } catch (e) {
      return _sanitizeVideoPrompt(originalPrompt);
    }
  }

  // ==================== 图生图（动态 image 模型） ====================
  Future<String> generateImageWithCharacterReference(String prompt, {required List<String> characterImageUrls}) async {
    if (ApiConfig.USE_MOCK_IMAGE_API) return ApiConfig.MOCK_IMAGE_URL;
    try {
      final dio = await ApiConfig.getRequiredDio('image');
      final model = await ApiConfig.getRequiredModel('image');

      final contentItems = <Map<String, dynamic>>[{'type': 'text', 'text': prompt}];
      for (final url in characterImageUrls) {
        if (url.isNotEmpty) {
          contentItems.add({'type': 'image_url', 'image_url': {'url': url}});
        }
      }

      final requestBody = {'model': model, 'stream': false, 'messages': [{'role': 'user', 'content': contentItems}]};
      final response = await dio.post('/v1/chat/completions', data: requestBody);

      if (response.statusCode == 200) {
        final choices = response.data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final content = choices[0]['message']['content'];
          if (content is String) {
            final match = RegExp(r'https://pro\.filesystem\.site/cdn/[^\s\])"]+').firstMatch(content);
            if (match != null) return match.group(0)!;
            if (content.startsWith('http')) return content;
          } else if (content is List) {
            for (final item in content) {
              if (item['type'] == 'image_url') return item['image_url']?['url'];
            }
          }
        }
      }
      throw Exception('图生图失败：未找到图片 URL');
    } catch (e) {
      return generateImage(prompt);
    }
  }

  // ==================== 角色三视图（动态 image 模型） ====================
  Future<CharacterSheet> generateCharacterSheets(String characterName, String description, {List<String>? referenceImages, void Function(double, String)? onProgress}) async {
    if (ApiConfig.USE_MOCK_CHARACTER_SHEET_API) {
      await Future.delayed(const Duration(milliseconds: 500));
      return CharacterSheet(id: 'char_${DateTime.now().millisecondsSinceEpoch}', characterId: 'char_${characterName.hashCode}', characterName: characterName, description: description, role: '主角', combinedViewUrl: ApiConfig.MOCK_CHARACTER_COMBINED_URL, status: CharacterSheetStatus.completed);
    }
    try {
      onProgress?.call(0.2, '生成组合三视图...');
      final combinedPrompt = _buildCombinedViewPrompt(description);
      final combinedUrl = await generateImage(combinedPrompt, referenceImages: referenceImages);
      return CharacterSheet(id: 'char_${DateTime.now().millisecondsSinceEpoch}', characterId: 'char_${characterName.hashCode}', characterName: characterName, description: description, role: '主角', combinedViewUrl: combinedUrl, status: CharacterSheetStatus.completed);
    } catch (e) {
      throw Exception('角色三视图生成失败: $e');
    }
  }

  String _buildCombinedViewPrompt(String description) {
    return 'Character turnaround sheet with three views side by side:\nLEFT: Front view\nCENTER: Side view\nRIGHT: Back view\nCharacter: ${description.isEmpty ? 'A character in anime/manga style' : description}\nStyle: anime/manga art style, clean line art, flat colors, professional character design sheet\nBackground: plain white or light gray background\nComposition: all three views same size, equal spacing, full body visible, neutral standing pose';
  }

  Future<List<CharacterSheet>> generateMultipleCharacterSheets(List<Map<String, String>> characters, {List<String>? referenceImages, void Function(double, String)? onProgress}) async {
    final List<CharacterSheet> sheets = [];
    for (int i = 0; i < characters.length; i++) {
      final char = characters[i];
      onProgress?.call(i / characters.length, '正在生成 ${char['name']} 的三视图...');
      sheets.add(await generateCharacterSheets(char['name'] ?? '角色${i + 1}', char['description'] ?? '', referenceImages: referenceImages));
    }
    onProgress?.call(1.0, '所有角色三视图生成完成！');
    return sheets;
  }

  // ==================== 视频生成（动态 video 模型） ====================
  Future<VideoGenerationResponse> generateVideo({
    required String prompt,
    List<String> imageUrls = const [],
    String seconds = '10',
    String model = '',
    String size = '1280x720',
    bool sanitizePrompt = false,
  }) async {
    if (ApiConfig.USE_MOCK_VIDEO_API) {
      await Future.delayed(const Duration(seconds: 2));
      return VideoGenerationResponse(id: 'mock_task_${DateTime.now().millisecondsSinceEpoch}', object: 'video', model: model, status: 'completed', progress: 100, createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000, seconds: seconds, videoUrl: ApiConfig.MOCK_VIDEO_URL);
    }

    try {
      final dio = await ApiConfig.getRequiredDio('video');
      String finalModel = model;
      if (finalModel.isEmpty || finalModel == 'veo3.1-components') {
        finalModel = await ApiConfig.getRequiredModel('video');
      }

      final finalPrompt = sanitizePrompt ? _sanitizeVideoPrompt(prompt) : prompt;
      final formData = FormData.fromMap({
        'model': finalModel,
        'prompt': finalPrompt,
        'seconds': seconds,
        'size': size,
        'watermark': 'false',
      });
      for (final imageUrl in imageUrls) {
        formData.fields.add(MapEntry('input_reference', imageUrl));
      }

      final response = await dio.post('/v1/videos', data: formData);
      return VideoGenerationResponse.fromJson(response.data);
    } catch (e) {
      throw Exception('视频生成错误: $e');
    }
  }

  Future<VideoGenerationResponse> pollVideoStatus({
    required String taskId,
    Duration timeout = const Duration(minutes: 10),
    Duration interval = const Duration(seconds: 2),
    void Function(int, String)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (ApiConfig.USE_MOCK_VIDEO_API) {
      for (int progress = 0; progress <= 100; progress += 25) {
        if (isCancelled?.call() == true) throw Exception('操作已取消');
        await Future.delayed(const Duration(milliseconds: 500));
        onProgress?.call(progress, 'in_progress');
      }
      return VideoGenerationResponse(id: taskId, object: 'video', model: 'veo3.1', status: 'completed', progress: 100, createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000, seconds: '10', videoUrl: ApiConfig.MOCK_VIDEO_URL);
    }

    final dio = await ApiConfig.getRequiredDio('video');
    final startTime = DateTime.now();
    while (true) {
      if (isCancelled?.call() == true) throw Exception('操作已取消');
      if (DateTime.now().difference(startTime) > timeout) throw Exception('视频生成超时');
      
      final response = await dio.get('/v1/videos/$taskId');
      final result = VideoGenerationResponse.fromJson(response.data);
      onProgress?.call(result.progress ?? 0, result.status ?? 'unknown');

      if (result.isCompleted) return result;
      if (result.isFailed) throw Exception('视频生成失败: ${result.error ?? "未知错误"}');

      for (int i = 0; i < 5; i++) {
        await Future.delayed(interval ~/ 5);
        if (isCancelled?.call() == true) throw Exception('操作已取消');
      }
    }
  }

  // ==================== 通用文件下载 ====================
  Future<File> downloadFile(String url, {String? filename}) async {
    try {
      final response = await Dio().get(url, options: Options(responseType: ResponseType.bytes));
      final tempDir = await getTemporaryDirectory();
      final finalFilename = filename ?? 'file_${DateTime.now().millisecondsSinceEpoch}${path.extension(url)}';
      final file = File(path.join(tempDir.path, finalFilename));
      await file.writeAsBytes(response.data as List<int>);
      return file;
    } catch (e) {
      throw Exception('文件下载错误: $e');
    }
  }
}