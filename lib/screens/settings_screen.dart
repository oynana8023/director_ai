import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:url_launcher/url_launcher.dart';

// ==================== 动态配置引用 ====================
import '../models/llm_config.dart';
import '../services/llm_config_store.dart';
import '../services/llm_provider.dart';
import '../utils/model_capability.dart';
import '../services/api_config_service.dart';
// =======================================================

import '../providers/conversation_provider.dart';
import '../providers/video_merge_provider.dart';
import '../providers/chat_provider.dart';
import '../models/screenplay.dart';
import '../models/script.dart';
import '../services/video_merger_service.dart';

/// 设置页面
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ==================== 动态配置状态 ====================
  final _configStore = LLMConfigStore();
  List<LLMConfig> _customConfigs = [];
  Map<String, UsageBinding> _bindings = {}; // 记录每个功能绑定的配置+模型
  // =======================================================

  @override
  void initState() {
    super.initState();
    _loadCustomConfigs();
    _loadBindings();
  }

  Future<void> _loadCustomConfigs() async {
    final configs = await _configStore.loadAll();
    if (mounted) setState(() => _customConfigs = configs);
  }

  Future<void> _loadBindings() async {
    final bindings = await _configStore.getBindings();
    if (mounted) setState(() => _bindings = bindings);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9FC),
      appBar: AppBar(
        title: const Text(
          '设置',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E)),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1C1C1E)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer2<ConversationProvider, VideoMergeProvider>(
        builder: (context, convProvider, mergeProvider, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildApiConfigCard(context),
              const SizedBox(height: 24),
              _buildCacheManagementCard(context, convProvider),
              const SizedBox(height: 24),
              _buildDatabaseCard(context),
              const SizedBox(height: 24),
              _buildVideoMergeCard(context, mergeProvider),
              const SizedBox(height: 24),
              _buildAboutCard(context),
            ],
          );
        },
      ),
    );
  }

  /// API 配置卡片
  Widget _buildApiConfigCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF3B82F6)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.api_outlined, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('API 配置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E))),
                      SizedBox(height: 2),
                      Text('配置各服务的 API Key', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 老 Key（保留兼容，但已不生效）
          _buildApiKeyRow(
            context, '智谱 GLM-4.7', ApiConfigService.maskApiKey(ApiConfigService.getZhipuApiKey()),
            Icons.psychology_outlined, const Color(0xFF8B5CF6),
            () => _showApiKeyEditDialog(context, '智谱 GLM API Key',
                ApiConfigService.getZhipuApiKey(), (key) => ApiConfigService.setZhipuApiKey(key)),
          ),
          _buildPromoRow(context, '🚀 智谱 GLM Coding 超值订阅', '20+ 编程工具无缝支持，限时惊喜价！',
              const Color(0xFF8B5CF6), 'https://www.bigmodel.cn/glm-coding?ic=BUXAZXR3YZ'),
          const Divider(height: 1),

          _buildApiKeyRow(
            context, '视频生成 (tuzi-api)', ApiConfigService.maskApiKey(ApiConfigService.getVideoApiKey()),
            Icons.videocam_outlined, const Color(0xFFEC4899),
            () => _showApiKeyEditDialog(context, '视频生成 API Key',
                ApiConfigService.getVideoApiKey(), (key) => ApiConfigService.setVideoApiKey(key)),
          ),
          const Divider(height: 1),

          _buildApiKeyRow(
            context, '图像生成 (tuzi-api)', ApiConfigService.maskApiKey(ApiConfigService.getImageApiKey()),
            Icons.image_outlined, const Color(0xFFF59E0B),
            () => _showApiKeyEditDialog(context, '图像生成 API Key',
                ApiConfigService.getImageApiKey(), (key) => ApiConfigService.setImageApiKey(key)),
          ),
          _buildPromoRow(context, '🎁 邀请注册获额度', '邀请好友双方各得 \$0.4 额度',
              const Color(0xFFEC4899), 'https://api.tu-zi.com/register?aff=zTvc'),
          const Divider(height: 1),

          _buildApiKeyRow(
            context, '豆包 ARK (图片识别)', ApiConfigService.maskApiKey(ApiConfigService.getDoubaoApiKey()),
            Icons.visibility_outlined, const Color(0xFF10B981),
            () => _showApiKeyEditDialog(context, '豆包 API Key',
                ApiConfigService.getDoubaoApiKey(), (key) => ApiConfigService.setDoubaoApiKey(key)),
          ),

          // ==================== 动态绑定区域 ====================
          const Divider(height: 1, thickness: 1),

          _buildBindingRow('对话模型', 'chat', Icons.chat_outlined),
          _buildBindingRow('视觉识别模型', 'vision', Icons.visibility_outlined),
          _buildBindingRow('图像生成模型', 'image', Icons.image_outlined),
          _buildBindingRow('视频生成模型', 'video', Icons.videocam_outlined),

          const Divider(height: 1, thickness: 1),

          // 已添加的自定义配置列表
          ..._customConfigs.map((config) => _buildDynamicConfigRow(config)),

          // 添加自定义模型的入口
          InkWell(
            onTap: () => _showAddCustomModelDialog(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.add_circle_outline, size: 18, color: Color(0xFF3B82F6)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('添加自定义 AI 模型', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E))),
                        SizedBox(height: 2),
                        Text('支持 OpenAI、火山云、文心一言等兼容接口', style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 20, color: Color(0xFF8E8E93)),
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text('提示：API Key 将保存在本地，仅用于此设备。',
                style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
          ),
        ],
      ),
    );
  }

  // ==================== 绑定行 ====================
  Widget _buildBindingRow(String label, String usage, IconData icon) {
    String? boundConfigName;
    String? boundModelName;
    final binding = _bindings[usage];
    if (binding != null) {
      for (final c in _customConfigs) {
        if (c.id == binding.configId) {
          boundConfigName = c.name;
          for (final m in c.models) {
            if (m.id == binding.modelId) { boundModelName = m.name; break; }
          }
          break;
        }
      }
    }

    final hasBinding = boundConfigName != null;
    return InkWell(
      onTap: () => _showBindingSelector(label, usage),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF3B82F6)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF1C1C1E))),
                  const SizedBox(height: 2),
                  Text(
                    hasBinding ? '$boundConfigName · ${boundModelName ?? binding!.modelId}' : '未绑定（点击选择）',
                    style: TextStyle(fontSize: 12, color: hasBinding ? const Color(0xFF10B981) : const Color(0xFFF87171)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFF8E8E93)),
          ],
        ),
      ),
    );
  }

  // ==================== 绑定选择器（支持同一 Key 下选不同模型） ====================
  void _showBindingSelector(String label, String usage) {
    if (_customConfigs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先添加至少一个自定义模型')));
      return;
    }

    final currentBinding = _bindings[usage];
    final currentValue = currentBinding == null ? null : '${currentBinding.configId}::${currentBinding.modelId}';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('选择【$label】使用的模型'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final config in _customConfigs) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                      child: Text(config.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    ...config.models.map((m) {
                      final value = '${config.id}::${m.id}';
                      return RadioListTile<String>(
                        dense: true,
                        title: Text(m.name, style: const TextStyle(fontSize: 13)),
                        subtitle: Text('${m.capability} · ${m.description}', style: const TextStyle(fontSize: 11)),
                        value: value,
                        groupValue: currentValue,
                        onChanged: (val) async {
                          if (val == null) return;
                          final parts = val.split('::');
                          await _configStore.setActiveConfig(usage, parts[0], parts[1]);
                          await ApiConfigService.refreshBindings();
                          await _loadBindings();
                          if (context.mounted) Navigator.pop(context);
                        },
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ],
        );
      },
    );
  }

  // ==================== 动态配置行 ====================
  Widget _buildDynamicConfigRow(LLMConfig config) {
    return InkWell(
      onTap: () => _showManageCustomConfigDialog(config),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.model_training, size: 18, color: Color(0xFF8B5CF6)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(config.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF1C1C1E))),
                  const SizedBox(height: 2),
                  Text('包含 ${config.models.length} 个模型', style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: const Text('自定义', style: TextStyle(fontSize: 10, color: Color(0xFF10B981))),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFF8E8E93)),
          ],
        ),
      ),
    );
  }

  // ==================== 添加自定义模型 ====================
  void _showAddCustomModelDialog(BuildContext context) {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final keyController = TextEditingController();
    List<LLMModel> fetchedModels = [];
    bool isFetching = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('添加自定义模型'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: '名称 (如 阿里百炼)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: urlController,
                        decoration: InputDecoration(
                          labelText: 'BaseURL (如 https://dashscope.aliyuncs.com/compatible-mode/v1)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: keyController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: isFetching ? null : () async {
                            if (urlController.text.trim().isEmpty || keyController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写 BaseURL 和 API Key')));
                              return;
                            }
                            setDialogState(() => isFetching = true);
                            try {
                              final tempConfig = LLMConfig(
                                id: 'temp',
                                name: nameController.text.trim(),
                                baseUrl: urlController.text.trim(),
                                apiKey: keyController.text.trim(),
                              );
                              final provider = LLMProvider(tempConfig);
                              final ids = await provider.fetchModels();
                              final models = ids.map((id) => ModelCapabilityResolver.resolve(id)).toList();
                              setDialogState(() {
                                fetchedModels = models;
                                isFetching = false;
                              });
                            } catch (e) {
                              setDialogState(() => isFetching = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                              }
                            }
                          },
                          icon: isFetching
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.cloud_download),
                          label: Text(isFetching ? '获取中...' : '获取模型列表'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      if (fetchedModels.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text('已获取到的模型（会全部保存）:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 8),
                        ...fetchedModels.map((m) => Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                            title: Text(m.name, style: const TextStyle(fontSize: 13)),
                            subtitle: Text('${m.capability} · ${m.description}', style: const TextStyle(fontSize: 11)),
                          ),
                        )),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                ElevatedButton(
                  onPressed: fetchedModels.isEmpty ? null : () async {
                    final newConfig = LLMConfig(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: nameController.text.trim().isEmpty ? '未命名厂家' : nameController.text.trim(),
                      baseUrl: urlController.text.trim(),
                      apiKey: keyController.text.trim(),
                      models: fetchedModels,
                      selectedModelId: null, // 不在配置级选，改到绑定时选
                    );
                    final updated = [..._customConfigs, newConfig];
                    await _configStore.saveAll(updated);
                    setState(() => _customConfigs = updated);
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('保存配置'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==================== 管理自定义配置 ====================
  void _showManageCustomConfigDialog(LLMConfig config) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(config.name),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BaseURL: ${config.baseUrl}', style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
                const SizedBox(height: 12),
                Text('包含 ${config.models.length} 个模型：', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                ...config.models.map((m) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('• ${m.name}  (${m.capability})', style: const TextStyle(fontSize: 13)),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final updated = _customConfigs.where((c) => c.id != config.id).toList();
                await _configStore.saveAll(updated);
                setState(() => _customConfigs = updated);
                if (context.mounted) Navigator.pop(context);
              },
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFF87171)),
              child: const Text('删除此配置'),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
          ],
        );
      },
    );
  }

  // ==================== 原有辅助方法 ====================
  Widget _buildPromoRow(BuildContext context, String title, String description, Color color, String url) {
    return InkWell(
      onTap: () => _launchUrl(url),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [color.withOpacity(0.08), color.withOpacity(0.03)])),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.card_giftcard_outlined, size: 16, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
                  const SizedBox(height: 2),
                  Text(description, style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.3), width: 1),
              ),
              child: Text('查看', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: color.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildApiKeyRow(BuildContext context, String label, String maskedKey, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF1C1C1E))),
                  const SizedBox(height: 2),
                  Text(maskedKey, style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93), fontFamily: 'monospace')),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFF8E8E93)),
          ],
        ),
      ),
    );
  }

  Future<void> _showApiKeyEditDialog(BuildContext context, String title, String currentValue, Future<void> Function(String) onSave) async {
    final controller = TextEditingController(text: currentValue);
    bool isVisible = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                obscureText: !isVisible,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  hintText: '请输入 API Key',
                  suffixIcon: IconButton(
                    icon: Icon(isVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setDialogState(() => isVisible = !isVisible),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text('提示：API Key 将保存在本地，仅用于此设备。', style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('API Key 不能为空'), backgroundColor: Color(0xFFF87171)));
                  return;
                }
                Navigator.pop(context, true);
              },
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (result == true && context.mounted) {
      try {
        await onSave(controller.text.trim());
        if (context.mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('API Key 已保存'), backgroundColor: Color(0xFF10B981), behavior: SnackBarBehavior.floating));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e'), backgroundColor: const Color(0xFFF87171), behavior: SnackBarBehavior.floating));
        }
      }
    }
  }

  // ==================== 以下为原有其他模块，全部保留 ====================

  Widget _buildCacheManagementCard(BuildContext context, ConversationProvider provider) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(width: 36, height: 36, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)]), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.storage_outlined, color: Colors.white, size: 20)),
                const SizedBox(width: 12),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('缓存管理', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E))), SizedBox(height: 2), Text('自动清理 2 天未访问的缓存', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)))])),
              ],
            ),
          ),
          FutureBuilder<CacheStats>(
            future: provider.getCacheStats(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
              final stats = snapshot.data!;
              return Column(
                children: [
                  _buildStatRow('总缓存大小', stats.totalSizeFormatted, Icons.sd_storage_outlined),
                  const Divider(height: 1),
                  _buildStatRow('缓存文件数', '${stats.fileCount} 个', Icons.insert_drive_file_outlined),
                  const Divider(height: 1),
                  _buildStatRow('图片数量', '${stats.imageCount} 张', Icons.image_outlined),
                  const Divider(height: 1),
                  _buildStatRow('视频数量', '${stats.videoCount} 个', Icons.videocam_outlined),
                ],
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => _clearExpiredCache(context, provider), icon: const Icon(Icons.cleaning_services_outlined, size: 20), label: const Text('清理过期缓存'), style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => _clearAllCache(context, provider), icon: const Icon(Icons.delete_sweep_outlined, size: 20), label: const Text('清空所有缓存'), style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFF87171), side: const BorderSide(color: Color(0xFFF87171)), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF8B5CF6)),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF8E8E93))),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E))),
        ],
      ),
    );
  }

  Widget _buildVideoMergeCard(BuildContext context, VideoMergeProvider provider) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(width: 36, height: 36, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)]), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.video_library_outlined, color: Colors.white, size: 20)),
                const SizedBox(width: 12),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('视频合并', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E))), SizedBox(height: 2), Text('将场景视频合并为完整视频', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)))])),
              ],
            ),
          ),
          _buildStatRow('已合并视频', '${provider.mergedVideosCount} 个', Icons.video_collection_outlined),
          const Divider(height: 1),
          _buildStatRow('占用空间', provider.mergedVideosSizeFormatted, Icons.sd_storage_outlined),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: OutlinedButton.icon(onPressed: () => _testMergeWithMockVideos(context, provider), icon: const Icon(Icons.science, size: 18), label: const Text('🧪 测试7场景合并'), style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF8B5CF6), side: const BorderSide(color: Color(0xFF8B5CF6)), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
          ),
          if (VideoMergerService.useMockMode)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFEDE9FE), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFA78BFA))),
              child: const Row(children: [Icon(Icons.science, color: Color(0xFF7C3AED), size: 20), SizedBox(width: 8), Expanded(child: Text('Mock 模式：模拟合并流程，实际下载第一个视频', style: TextStyle(color: Color(0xFF7C3AED), fontSize: 13)))]),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: provider.isMerging ? null : () => _showMergeDialog(context, provider), icon: provider.isMerging ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.merge_type_outlined, size: 20), label: Text(provider.isMerging ? provider.statusMessage : '合并场景视频'), style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEC4899), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
                if (provider.isMerging) Padding(padding: const EdgeInsets.only(top: 12), child: LinearProgressIndicator(value: provider.progress, backgroundColor: const Color(0xFFF3F4F6), valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFEC4899)))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatabaseCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(width: 36, height: 36, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)]), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.storage, color: Colors.white, size: 20)),
                const SizedBox(width: 12),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('数据库查看', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E))), SizedBox(height: 2), Text('查看会话和消息数据', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)))])),
              ],
            ),
          ),
          Consumer<ConversationProvider>(
            builder: (context, provider, child) {
              return Column(
                children: [
                  _buildStatRow('会话数量', '${provider.conversations.length} 个', Icons.folder_outlined),
                  const Divider(height: 1),
                  if (provider.currentConversation != null) _buildStatRow('当前会话消息', '${provider.currentMessages.length} 条', Icons.message_outlined),
                  if (provider.currentConversation != null) const Divider(height: 1),
                  _buildStatRow('数据库路径', 'hive_db/', Icons.folder_open_outlined),
                ],
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => _showDatabaseViewer(context), icon: const Icon(Icons.table_view_outlined, size: 20), label: const Text('查看数据详情'), style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B82F6), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => _exportDatabase(context), icon: const Icon(Icons.download_outlined, size: 20), label: const Text('导出数据 (JSON)'), style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF8B5CF6), side: const BorderSide(color: Color(0xFF8B5CF6)), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(width: 36, height: 36, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)]), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.info_outline, color: Colors.white, size: 20)),
                const SizedBox(width: 12),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('关于', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E))), SizedBox(height: 2), Text('AI 漫导 - 将创意转化为动漫视频', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)))])),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildAboutRow('版本', '1.0.0'),
                const SizedBox(height: 12),
                _buildAboutRow('数据库', 'Hive (轻量级 NoSQL)'),
                const SizedBox(height: 12),
                _buildAboutRow('缓存策略', '2 天未访问自动清理'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutRow(String label, String value) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF8E8E93)))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 14, color: Color(0xFF1C1C1E)))),
      ],
    );
  }

  Future<void> _clearExpiredCache(BuildContext context, ConversationProvider provider) async {
    showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
    try {
      final result = await provider.clearAllCache();
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('清理完成：删除 ${result.removedCount} 个文件，释放 ${result.freedSpaceFormatted}'), backgroundColor: const Color(0xFF10B981), behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('清理失败: $e'), backgroundColor: const Color(0xFFF87171), behavior: SnackBarBehavior.floating));
      }
    }
  }

  Future<void> _clearAllCache(BuildContext context, ConversationProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('清空所有缓存'),
        content: const Text('确定要清空所有缓存吗？这将释放所有缓存空间，但不会删除对话记录。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF87171)), child: const Text('清空')),
        ],
      ),
    );
    if (confirmed == true) {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
      try {
        await provider.clearAllCacheForce();
        if (context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清空所有缓存'), backgroundColor: Color(0xFF10B981), behavior: SnackBarBehavior.floating));
        }
      } catch (e) {
        if (context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('清空失败: $e'), backgroundColor: const Color(0xFFF87171), behavior: SnackBarBehavior.floating));
        }
      }
    }
  }

  Future<void> _showMergeDialog(BuildContext context, VideoMergeProvider provider) async {
    final chatProvider = context.read<ChatProvider>();
    final currentScreenplay = chatProvider.screenplayController.currentScreenplay;
    if (currentScreenplay == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('当前没有可合并的剧本，请先完成视频生成'), backgroundColor: Color(0xFFF87171), behavior: SnackBarBehavior.floating));
      return;
    }
    final scenesWithVideo = currentScreenplay.scenes.where((s) => s.videoUrl != null).length;
    if (scenesWithVideo == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('当前剧本没有已生成的视频'), backgroundColor: Color(0xFFF87171), behavior: SnackBarBehavior.floating));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('合并场景视频'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('剧本: ${currentScreenplay.scriptTitle}'),
            const SizedBox(height: 8),
            Text('场景数: ${currentScreenplay.scenes.length}'),
            const SizedBox(height: 8),
            Text('已生成视频: $scenesWithVideo 个'),
            const SizedBox(height: 16),
            const Text('是否将这些场景视频合并为完整视频？', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEC4899)), child: const Text('开始合并')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      showDialog(context: context, barrierDismissible: false, builder: (context) => _MergeProgressDialog(screenplay: currentScreenplay));
      provider.mergeVideos(currentScreenplay);
    }
  }

  Future<void> _testMergeWithMockVideos(BuildContext context, VideoMergeProvider provider) async {
    final mockScreenplay = Screenplay(
      taskId: 'test_${DateTime.now().millisecondsSinceEpoch}',
      scriptTitle: '🧪 7场景视频合并测试',
      scenes: [
        Scene(sceneId: 1, narration: '测试场景 1', imagePrompt: 'Scene 1', videoPrompt: 'Camera panning', characterDescription: 'Test', videoUrl: 'https://filesystem.site/cdn/20260104/2e0938b114576d0217175cfa925e2a.mp4', status: SceneStatus.completed),
        Scene(sceneId: 2, narration: '测试场景 2', imagePrompt: 'Scene 2', videoPrompt: 'Camera zooming', characterDescription: 'Test', videoUrl: 'https://filesystem.site/cdn/20260104/6035dcf051bf3bf69dde8fec7c873c.mp4', status: SceneStatus.completed),
        Scene(sceneId: 3, narration: '测试场景 3', imagePrompt: 'Scene 3', videoPrompt: 'Camera tracking', characterDescription: 'Test', videoUrl: 'https://filesystem.site/cdn/20260104/a2a3187da7a7b2edaee219ccf38c53.mp4', status: SceneStatus.completed),
        Scene(sceneId: 4, narration: '测试场景 4', imagePrompt: 'Scene 4', videoPrompt: 'Camera rotating', characterDescription: 'Test', videoUrl: 'https://filesystem.site/cdn/20260104/19bea6cc8e95b5865fae775424c521.mp4', status: SceneStatus.completed),
        Scene(sceneId: 5, narration: '测试场景 5', imagePrompt: 'Scene 5', videoPrompt: 'Camera dollying', characterDescription: 'Test', videoUrl: 'https://filesystem.site/cdn/20260104/8b9e9d86218d8eeb26caddb2e921e6.mp4', status: SceneStatus.completed),
        Scene(sceneId: 6, narration: '测试场景 6', imagePrompt: 'Scene 6', videoPrompt: 'Camera crane', characterDescription: 'Test', videoUrl: 'https://filesystem.site/cdn/20260104/3f071fce050dbeac6298af16a5d31a.mp4', status: SceneStatus.completed),
        Scene(sceneId: 7, narration: '测试场景 7', imagePrompt: 'Scene 7', videoPrompt: 'Camera tracking final', characterDescription: 'Test', videoUrl: 'https://filesystem.site/cdn/20260104/8481a78572cecac738b1703924ae10.mp4', status: SceneStatus.completed),
      ],
      status: ScreenplayStatus.completed,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [Icon(Icons.science, color: Color(0xFF8B5CF6)), SizedBox(width: 8), Text('Mock 测试')]),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('将使用 7 个测试视频进行合并流程演示。'),
            SizedBox(height: 12),
            Text('注：Mock 模式下实际只下载第一个视频作为"合并结果"', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)), child: const Text('开始测试')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      showDialog(context: context, barrierDismissible: false, builder: (context) => _MergeProgressDialog(screenplay: mockScreenplay));
      provider.mergeVideos(mockScreenplay);
    }
  }

  void _showDatabaseViewer(BuildContext context) {
    final provider = context.read<ConversationProvider>();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('数据库内容'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('会话总数: ${provider.conversations.length}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 16),
                if (provider.conversations.isEmpty)
                  const Text('暂无会话数据', style: TextStyle(color: Color(0xFF8E8E93)))
                else
                  ...provider.conversations.take(5).map((conv) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(conv.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text('消息: ${conv.messageCount} | ${conv.updatedAt.toString().substring(0, 19)}', style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
                          ],
                        ),
                      )),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
      ),
    );
  }

  Future<void> _exportDatabase(BuildContext context) async {
    final provider = context.read<ConversationProvider>();
    showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
    try {
      final exportData = {
        'conversations': provider.conversations.map((conv) => {
          'id': conv.id,
          'title': conv.title,
          'createdAt': conv.createdAt.toIso8601String(),
          'updatedAt': conv.updatedAt.toIso8601String(),
          'messageCount': conv.messageCount,
          'isPinned': conv.isPinned,
        }).toList(),
        'exportTime': DateTime.now().toIso8601String(),
        'version': '1.0.0',
      };
      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
      if (context.mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('导出成功'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('已导出 ${provider.conversations.length} 个会话'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8)),
                  child: SelectableText(
                    jsonString.substring(0, jsonString.length > 500 ? 500 : jsonString.length) + (jsonString.length > 500 ? '\n\n... (已截断)' : ''),
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败: $e'), backgroundColor: const Color(0xFFF87171), behavior: SnackBarBehavior.floating));
      }
    }
  }
}

class _MergeProgressDialog extends StatelessWidget {
  final Screenplay screenplay;
  const _MergeProgressDialog({required this.screenplay});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('正在合并视频'),
      content: Consumer<VideoMergeProvider>(
        builder: (context, provider, child) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(provider.statusMessage, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: provider.progress, backgroundColor: const Color(0xFFF3F4F6), valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFEC4899))),
              const SizedBox(height: 8),
              Text('${(provider.progress * 100).toInt()}%', style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
              if (provider.errorMessage != null) ...[const SizedBox(height: 8), Text(provider.errorMessage!, style: const TextStyle(fontSize: 12, color: Color(0xFFF87171)))],
            ],
          );
        },
      ),
      actions: [
        Consumer<VideoMergeProvider>(
          builder: (context, provider, child) {
            if (provider.hasError) return FilledButton(onPressed: () { provider.reset(); Navigator.pop(context); }, style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF87171)), child: const Text('关闭'));
            if (provider.isCompleted) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (provider.mergedVideoFile != null)
                    TextButton.icon(
                      onPressed: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => _MergedVideoPlayerScreen(videoFile: provider.mergedVideoFile!))); },
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('播放视频'),
                    ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: () { provider.reset(); Navigator.pop(context); }, style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)), child: const Text('完成')),
                ],
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}

class _MergedVideoPlayerScreen extends StatefulWidget {
  final File videoFile;
  const _MergedVideoPlayerScreen({required this.videoFile});

  @override
  State<_MergedVideoPlayerScreen> createState() => _MergedVideoPlayerScreenState();
}

class _MergedVideoPlayerScreenState extends State<_MergedVideoPlayerScreen> {
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;
  bool _isInitialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      _videoController = VideoPlayerController.file(widget.videoFile);
      await _videoController.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _videoController,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoController.value.aspectRatio,
        placeholder: Container(color: Colors.black, child: const Center(child: CircularProgressIndicator(color: Colors.white))),
        errorBuilder: (context, errorMessage) => Center(child: Text('播放失败: $errorMessage', style: const TextStyle(color: Colors.white))),
      );
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      if (mounted) setState(() => _error = '初始化播放器失败: $e');
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('合并视频预览'),
        actions: [
          IconButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('视频文件'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('文件路径:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SelectableText(widget.videoFile.path, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
                ),
              );
            },
            icon: const Icon(Icons.info_outline),
            tooltip: '文件信息',
          ),
        ],
      ),
      body: Center(
        child: _error != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                ],
              )
            : !_isInitialized
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text('加载视频中...', style: TextStyle(color: Colors.white)),
                    ],
                  )
                : Chewie(controller: _chewieController!),
      ),
    );
  }
}