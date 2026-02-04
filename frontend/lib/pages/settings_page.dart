import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/developer_mode_provider.dart';
import '../services/app_config_service.dart';
import '../theme_provider/theme_provider.dart';

/// Settings page for app configuration
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _backendUrlController = TextEditingController();
  bool _urlModified = false;

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
          // Appearance Section
          _buildSectionHeader('Appearance'),
          Card(
            child: SwitchListTile(
              title: const Text('Dark Mode'),
              subtitle: Text(themeProvider.isDarkMode ? 'On' : 'Off'),
              value: themeProvider.isDarkMode,
              onChanged: (_) => themeProvider.toggleTheme(),
              secondary: Icon(
                themeProvider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                color: colorScheme.primary,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Developer Section (only visible when dev mode is enabled)
          if (devMode.isEnabled) ...[
            _buildSectionHeader('Developer Options', color: Colors.orange),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.cloud, color: Colors.orange),
                    title: const Text('Backend URL'),
                    subtitle: Text(config.backendUrl),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: _backendUrlController,
                      decoration: InputDecoration(
                        hintText: 'http://127.0.0.1:8000',
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
                            _backendUrlController.text =
                                AppConfigService.defaultUrl;
                            setState(() => _urlModified = false);
                          },
                          icon: const Icon(Icons.restore, size: 18),
                          label: const Text('Reset to Default'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.developer_mode_outlined,
                    color: Colors.orange),
                title: const Text('Developer Mode'),
                subtitle: const Text('Enabled'),
                trailing: TextButton(
                  onPressed: () {
                    devMode.disable();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Developer mode disabled'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: const Text('Disable'),
                ),
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
}
