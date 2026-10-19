import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  static const appName = 'WITRN Analyzer';
  static const projectUrl = 'https://github.com/lxdklp/witrn_analyzer';
  static const iconAsset = 'assets/branding/witrn_analyzer_windows.png';

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  Future<void> _openLink(String url) async {
    try {
      if (await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Keep the URL available if no browser is installed or launch fails.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('无法打开浏览器，可复制链接后手动访问。'),
        action: SnackBarAction(
          label: '复制链接',
          onPressed: () =>
              unawaited(Clipboard.setData(ClipboardData(text: url))),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于')),
    body: SafeArea(
      top: false,
      child: FutureBuilder<PackageInfo>(
        future: _packageInfo,
        builder: (context, snapshot) {
          final info = snapshot.data;
          final version = info == null
              ? null
              : '${info.version}${info.buildNumber.isEmpty ? '' : ' (${info.buildNumber})'}';
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 960;
              final overview = _overview(
                context,
                version ?? (snapshot.hasError ? '版本信息暂不可用' : '正在读取版本…'),
              );
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _links(context, version),
                  const SizedBox(height: 24),
                  _credits(),
                ],
              );
              return SingleChildScrollView(
                padding: EdgeInsets.all(wide ? 24 : 16),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: overview),
                          const SizedBox(width: 24),
                          Expanded(child: details),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          overview,
                          const SizedBox(height: 24),
                          details,
                        ],
                      ),
              );
            },
          );
        },
      ),
    ),
  );

  Widget _overview(BuildContext context, String version) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 32,
              runSpacing: 16,
              children: [
                Image.asset(
                  AboutScreen.iconAsset,
                  width: 96,
                  height: 96,
                  semanticLabel: AboutScreen.appName,
                ),
                const FlutterLogo(size: 72),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              AboutScreen.appName,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              version,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              '基于 Flutter 的跨平台 WITRN K2 USB 功率计上位机。\n用于 USB PD 报文分析、电参曲线查看与采集数据导入导出。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Text('开源声明', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('本项目采用 GNU GPL v3 开源协议，使用、修改与分发时请遵守相应许可条款。'),
            const SizedBox(height: 24),
            Text(
              'Copyright © 2026 lxdklp',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _links(BuildContext context, String? version) => Card.outlined(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        const ListTile(title: Text('项目与支持')),
        _link('GitHub 项目主页', AboutScreen.projectUrl, Icons.code),
        _link(
          '版本发布',
          '${AboutScreen.projectUrl}/releases',
          Icons.download_outlined,
        ),
        _link(
          'BUG 反馈与建议',
          '${AboutScreen.projectUrl}/issues',
          Icons.bug_report_outlined,
        ),
        _link('作者', 'https://github.com/lxdklp', Icons.person_outline),
        const Divider(height: 1),
        _link(
          'GNU GPL v3',
          'https://www.gnu.org/licenses/gpl-3.0.html',
          Icons.description_outlined,
        ),
        ListTile(
          leading: const Icon(Icons.policy_outlined),
          title: const Text('第三方许可'),
          subtitle: const Text('查看依赖库的许可与版权声明'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLicensePage(
            context: context,
            applicationName: AboutScreen.appName,
            applicationVersion: version,
            applicationIcon: Image.asset(
              AboutScreen.iconAsset,
              width: 64,
              height: 64,
            ),
            applicationLegalese: 'Copyright © 2026 lxdklp',
          ),
        ),
      ],
    ),
  );

  Widget _credits() => Card.outlined(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        const ListTile(
          title: Text('鸣谢'),
          subtitle: Text('感谢以下项目及依赖库的贡献者，排名不分先后。'),
        ),
        _link(
          'Flutter',
          'https://flutter.dev',
          Icons.info,
          description: '跨平台界面与 Material Design 组件',
        ),
        _link(
          'hid_tool',
          'https://github.com/ArdWang/hid_tool',
          Icons.info,
          description: 'USB HID 设备通信',
        ),
        _link(
          'witrn_pd_sniffer',
          'https://github.com/JohnScotttt/witrn_pd_sniffer',
          Icons.info,
          description: '实现参考',
        ),
        const ListTile(
          title: Text('提交问题、建议与贡献的各位'),
          subtitle: Text('感谢大家帮助完善 WITRN Analyzer。'),
        ),
      ],
    ),
  );

  Widget _link(
    String title,
    String url,
    IconData icon, {
    String? description,
  }) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(description ?? url),
    trailing: const Icon(Icons.open_in_new, size: 20),
    onTap: () => unawaited(_openLink(url)),
  );
}
