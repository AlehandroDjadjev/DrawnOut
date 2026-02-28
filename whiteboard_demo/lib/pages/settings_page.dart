import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../providers/developer_mode_provider.dart';
import '../services/app_config_service.dart';
import '../theme_provider.dart';

/// Settings page for app configuration
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _backendUrlController = TextEditingController();
  bool _urlModified = false;
  bool _testingBackend = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final config = Provider.of<AppConfigService>(context, listen: false);
      _backendUrlController.text = config.backendUrl;
    });
  }

  @override
  void dispose() {
    _backendUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final devMode = Provider.of<DeveloperModeProvider>(context);
    final config = Provider.of<AppConfigService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        foregroundColor: colorScheme.primary,
        elevation: 1,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Backend Section (needed for running on emulators/phones)
          _buildSectionHeader('Backend'),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: Icon(Icons.cloud, color: colorScheme.primary),
                  title: const Text('Backend URL'),
                  subtitle: Text(config.backendUrl),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Android emulator: use http://10.0.2.2:8000.\nPhysical phone: use your PC LAN IP (example: http://192.168.1.50:8000).',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.65),
                      height: 1.25,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _backendUrlController,
                    decoration: InputDecoration(
                      hintText: AppConfigService.defaultUrl,
                      border: const OutlineInputBorder(),
                      suffixIcon: _urlModified
                          ? IconButton(
                              icon: const Icon(Icons.check,
                                  color: Colors.green),
                              onPressed: _saveBackendUrl,
                            )
                          : null,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _urlModified = value != config.backendUrl;
                      });
                    },
                    onSubmitted: (_) => _saveBackendUrl(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          config.resetToDefault();
                          _backendUrlController.text = AppConfigService.defaultUrl;
                          setState(() => _urlModified = false);
                        },
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('Reset to Default'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _testingBackend ? null : _testBackend,
                        icon: _testingBackend
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.wifi_tethering, size: 18),
                        label: Text(_testingBackend ? 'Testing…' : 'Test'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Appearance Section
          _buildSectionHeader('Appearance'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Dark Mode'),
                  subtitle: Text(themeProvider.isDarkMode ? 'On' : 'Off'),
                  value: themeProvider.isDarkMode,
                  onChanged: (_) => themeProvider.toggleTheme(),
                  secondary: Icon(
                    themeProvider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                    color: colorScheme.primary,
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('High Contrast'),
                  subtitle: Text(themeProvider.isHighContrast ? 'On' : 'Off'),
                  value: themeProvider.isHighContrast,
                  onChanged: (_) => themeProvider.toggleHighContrast(),
                  secondary: Icon(
                    Icons.contrast,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Developer Section (only visible when dev mode is enabled)
          if (devMode.isEnabled) ...[
            _buildSectionHeader('Developer Options', color: Colors.orange),
            Card(
              child: Column(
                children: [
                  const ListTile(
                    leading: Icon(Icons.developer_mode_outlined,
                        color: Colors.orange),
                    title: Text('Developer mode enabled'),
                    subtitle: Text('Extra debug features enabled'),
                    trailing: Icon(Icons.check_circle, color: Colors.green),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Card(
              child: ListTile(
                leading: Icon(Icons.developer_mode_outlined, color: Colors.orange),
                title: Text('Developer Account'),
                subtitle: Text('Debug features enabled (managed via database)'),
                trailing: Icon(Icons.check_circle, color: Colors.green),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // About Section
          _buildSectionHeader('About'),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('DrawnOut'),
                  subtitle: Text('Version 1.0.0'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('View Source'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // Could open GitHub link
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color ?? Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  void _saveBackendUrl() {
    final config = Provider.of<AppConfigService>(context, listen: false);
    config.setBackendUrl(_backendUrlController.text);
    setState(() => _urlModified = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Backend URL updated'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _testBackend() async {
    final config = Provider.of<AppConfigService>(context, listen: false);
    final base = config.backendUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final url = '$base/api/lessons/list/';

    setState(() => _testingBackend = true);
    try {
      final resp = await http
          .get(Uri.parse(url), headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 6));

      if (!mounted) return;
      final ok = resp.statusCode >= 200 && resp.statusCode < 300;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '✅ Connected (${resp.statusCode})\n$url'
                : '❌ Backend error (${resp.statusCode})\n$url',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: ok ? Colors.green : Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Can\'t connect\n$url\n$e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _testingBackend = false);
    }
  }
}
