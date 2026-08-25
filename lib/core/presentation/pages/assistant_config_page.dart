import 'package:flutter/material.dart';

import '../../data/models/opencode_connection_config.dart';
import '../../../features/chat/domain/providers/chat_provider.dart';

class AssistantConfigPage extends StatefulWidget {
  const AssistantConfigPage({super.key, required this.provider});

  final ChatProvider provider;

  @override
  State<AssistantConfigPage> createState() => _AssistantConfigPageState();
}

class _AssistantConfigPageState extends State<AssistantConfigPage> {
  late ConnectionType _type;
  late TextEditingController _hostCtrl;
  late TextEditingController _portCtrl;
  late TextEditingController _basePathCtrl;
  late TextEditingController _authUserCtrl;
  late TextEditingController _authPasswordCtrl;
  late TextEditingController _agentCtrl;
  late TextEditingController _providerIdCtrl;
  late TextEditingController _modelIdCtrl;
  late TextEditingController _sshUserCtrl;
  late TextEditingController _sshPasswordCtrl;
  late TextEditingController _sshKeyPathCtrl;
  late TextEditingController _opencodePathCtrl;
  late TextEditingController _workingDirCtrl;
  late TextEditingController _timeoutCtrl;
  bool _useHttps = false;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final config = widget.provider.opencodeConfig;
    _type = config.type;
    _hostCtrl = TextEditingController(text: config.host);
    _portCtrl = TextEditingController(text: config.port.toString());
    _basePathCtrl = TextEditingController(text: config.basePath);
    _authUserCtrl = TextEditingController(text: config.username);
    _authPasswordCtrl = TextEditingController(text: config.password);
    _agentCtrl = TextEditingController(text: config.agent);
    _providerIdCtrl = TextEditingController(text: config.providerID);
    _modelIdCtrl = TextEditingController(text: config.modelID);
    _sshUserCtrl = TextEditingController(text: config.sshUser);
    _sshPasswordCtrl = TextEditingController(text: config.sshPassword);
    _sshKeyPathCtrl = TextEditingController(text: config.sshKeyPath);
    _opencodePathCtrl = TextEditingController(text: config.opencodePath);
    _workingDirCtrl = TextEditingController(text: config.workingDirectory);
    _timeoutCtrl =
        TextEditingController(text: config.timeoutSeconds.toString());
    _useHttps = config.useHttps;
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _basePathCtrl.dispose();
    _authUserCtrl.dispose();
    _authPasswordCtrl.dispose();
    _agentCtrl.dispose();
    _providerIdCtrl.dispose();
    _modelIdCtrl.dispose();
    _sshUserCtrl.dispose();
    _sshPasswordCtrl.dispose();
    _sshKeyPathCtrl.dispose();
    _opencodePathCtrl.dispose();
    _workingDirCtrl.dispose();
    _timeoutCtrl.dispose();
    super.dispose();
  }

  OpencodeConnectionConfig _buildConfig() {
    return OpencodeConnectionConfig(
      type: _type,
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 4096,
      useHttps: _useHttps,
      basePath: _basePathCtrl.text.trim(),
      sshUser: _sshUserCtrl.text.trim(),
      sshPassword: _sshPasswordCtrl.text.trim(),
      sshKeyPath: _sshKeyPathCtrl.text.trim(),
      opencodePath: _opencodePathCtrl.text.trim(),
      workingDirectory: _workingDirCtrl.text.trim(),
      timeoutSeconds: int.tryParse(_timeoutCtrl.text.trim()) ?? 300,
      username: _authUserCtrl.text.trim().isEmpty
          ? 'opencode'
          : _authUserCtrl.text.trim(),
      password: _authPasswordCtrl.text,
      agent: _agentCtrl.text.trim(),
      providerID: _providerIdCtrl.text.trim(),
      modelID: _modelIdCtrl.text.trim(),
    );
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });

    final config = _buildConfig();
    final error = await widget.provider.testOpencodeConnection(config);

    setState(() {
      _testing = false;
      _testResult = error == null ? '连接成功！' : '连接失败：$error';
    });
  }

  Future<void> _save() async {
    final config = _buildConfig();
    await widget.provider.saveOpencodeConfig(config);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配置已保存')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('助手连接配置'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 使用说明
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('使用说明', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text(
                      '助手功能需要连接到运行 opencode 的 PC。\n\n'
                      '常用部署方案（按推荐顺序）：\n'
                      '  ① Tailscale（推荐）：PC 与手机各装 Tailscale，'
                      '同一账号登录，手机端 host 填 PC 的 Tailscale IP（100.x.x.x）。\n'
                      '  ② Cloudflare Tunnel：在 PC 跑 `cloudflared tunnel --url http://localhost:4096`，'
                      '拿到 https://xxx.trycloudflare.com 这种 URL，勾选下方的 "HTTPS"。\n'
                      '  ③ 公网 VPS SSH 反向隧道：PC 端 ssh -R 4096:127.0.0.1:4096 user@vps，'
                      '手机端 host 填 VPS 公网 IP。\n'
                      '  ④ 局域网/同机调试：host 填 127.0.0.1 或局域网 IP。\n\n'
                      'PC 启动：opencode web --hostname 0.0.0.0 --port 4096\n'
                      '建议同时设置 OPENCODE_SERVER_PASSWORD（填到下方"Basic Auth 密码"）。',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 连接方式
            Text('连接方式', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<ConnectionType>(
              segments: const [
                ButtonSegment(
                  value: ConnectionType.http,
                  label: Text('HTTP API'),
                  icon: Icon(Icons.language),
                ),
                ButtonSegment(
                  value: ConnectionType.ssh,
                  label: Text('SSH'),
                  icon: Icon(Icons.terminal),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (v) => setState(() => _type = v.first),
            ),
            const SizedBox(height: 16),

            // 通用配置
            Text('服务器配置', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _hostCtrl,
              decoration: const InputDecoration(
                labelText: '主机地址',
                hintText: '127.0.0.1 或 192.168.1.100',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portCtrl,
              decoration: InputDecoration(
                labelText: _type == ConnectionType.http ? '端口' : 'SSH 端口',
                hintText: _type == ConnectionType.http ? '4096' : '22',
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _timeoutCtrl,
              decoration: const InputDecoration(
                labelText: '超时时间（秒）',
                hintText: '300',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),

            // HTTP 特有配置
            if (_type == ConnectionType.http) ...[
              Text('HTTP 配置', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _useHttps,
                onChanged: (v) => setState(() => _useHttps = v),
                title: const Text('使用 HTTPS'),
                subtitle: const Text(
                  '勾选 = https://（cloudflare tunnel / 自建 HTTPS 反代）\n'
                  '不勾选 = http://（localhost / Tailscale / SSH 隧道）',
                  style: TextStyle(fontSize: 12),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _basePathCtrl,
                decoration: const InputDecoration(
                  labelText: '路径前缀（可选）',
                  hintText: '留空：直接挂在根路径；填了则拼在 host:port 后面',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _authUserCtrl,
                decoration: const InputDecoration(
                  labelText: 'Basic Auth 用户名',
                  hintText: 'opencode',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _authPasswordCtrl,
                decoration: const InputDecoration(
                  labelText: 'Basic Auth 密码（对应 OPENCODE_SERVER_PASSWORD）',
                  hintText: '留空则不发送鉴权头',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _agentCtrl,
                decoration: const InputDecoration(
                  labelText: 'opencode agent',
                  hintText: 'build（默认） / plan 等',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _providerIdCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Provider ID（可选）',
                        hintText: 'anthropic',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _modelIdCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Model ID（可选）',
                        hintText: 'claude-sonnet-4-5',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // SSH 特有配置
            if (_type == ConnectionType.ssh) ...[
              Text('SSH 配置', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _sshUserCtrl,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  hintText: 'root',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sshPasswordCtrl,
                decoration: const InputDecoration(
                  labelText: '密码（可选，优先使用密钥）',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sshKeyPathCtrl,
                decoration: const InputDecoration(
                  labelText: 'SSH 密钥路径（可选）',
                  hintText: '~/.ssh/id_rsa',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // opencode 配置
            Text('opencode 配置', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _opencodePathCtrl,
              decoration: const InputDecoration(
                labelText: 'opencode 路径',
                hintText: 'opencode（从 PATH 查找）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _workingDirCtrl,
              decoration: const InputDecoration(
                labelText: '工作目录（可选）',
                hintText: '/home/user/project',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            // 测试连接
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: Text(_testing ? '测试中...' : '测试连接'),
              ),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 8),
              Text(
                _testResult!,
                style: TextStyle(
                  color: _testResult!.startsWith('连接成功')
                      ? Colors.green
                      : theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
