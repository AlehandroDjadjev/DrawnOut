import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import '../theme_provider.dart';
import '../services/app_config_service.dart';
import '../services/auth_service.dart';
import '../ui/apple_ui.dart';
import 'edit_username_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _userData;
  List<dynamic> _lessons = [];
  bool _isLoading = true;
  String? _errorMessage;

  String? get _apiUrl {
    try {
      final config = Provider.of<AppConfigService>(context, listen: false);
      final url = config.backendUrl.trim();
      if (url.isNotEmpty) {
        return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
      }
    } catch (_) {}

    final v = dotenv.env['API_URL']?.trim();
    return (v == null || v.isEmpty)
        ? null
        : (v.endsWith('/') ? v.substring(0, v.length - 1) : v);
  }

  String get _baseUrl => "${_apiUrl ?? ''}/api/";

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final apiUrl = _apiUrl;
    if (apiUrl == null) {
      setState(() {
        _errorMessage =
            'Missing API_URL. Check whiteboard_demo/assets/.env and restart the app.';
        _isLoading = false;
      });
      return;
    }

    try {
      final authService = AuthService(baseUrl: apiUrl);
      authService.onSessionExpired = () {
        if (mounted) Navigator.of(context).pushReplacementNamed('/login');
      };

      final userResponse = await authService.authenticatedGet(
        '${_baseUrl}auth/profile/',
      );

      final lessonsResponse = await authService.authenticatedGet(
        '${_baseUrl}lessons/list/',
      );

      if (!mounted) return;
      if (userResponse.statusCode == 200 && lessonsResponse.statusCode == 200) {
        setState(() {
          _userData = jsonDecode(userResponse.body);
          _lessons = jsonDecode(lessonsResponse.body);
        });
      } else {
        setState(() {
          _errorMessage =
              'Failed to load profile data. Backend at $apiUrl\n'
              'profile: HTTP ${userResponse.statusCode}, lessons: HTTP ${lessonsResponse.statusCode}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not connect to server';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _navigateToEditUsername() async {
    if (_userData == null) return;
    final updated = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            EditUsernamePage(currentUsername: _userData!['username']),
      ),
    );

    if (!mounted) return;

    if (updated == true) {
      _fetchProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Keep Profile reactive to theme changes.
    context.watch<ThemeProvider>().isDarkMode;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppleErrorBanner(message: _errorMessage!),
                const SizedBox(height: 12),
                ApplePrimaryButton(
                  label: 'Retry',
                  onPressed: _fetchProfile,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final username = (_userData?['username'] ?? '').toString();
    final firstName = (_userData?['first_name'] ?? '').toString();
    final lastName = (_userData?['last_name'] ?? '').toString();
    final fullName = ('$firstName $lastName').trim();
    final email = (_userData?['email'] ?? '').toString();
    final pfpUrl = (_userData?['pfp'] ?? '').toString();
    final hasPfp = pfpUrl.trim().isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppleCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                  backgroundImage: hasPfp ? NetworkImage(pfpUrl) : null,
                  child: !hasPfp
                      ? Icon(Icons.person, color: theme.colorScheme.primary)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        username,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (fullName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          fullName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.75),
                          ),
                        ),
                      ],
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          email,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.65),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _navigateToEditUsername,
                  tooltip: 'Edit username',
                  icon: Icon(
                    Icons.edit,
                    size: 20,
                    color: theme.colorScheme.onSurface.withOpacity(0.75),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const AppleSectionTitle(title: 'Your lessons'),
          const SizedBox(height: 10),
          if (_lessons.isEmpty)
            AppleCard(
              child: Text(
                'You are not enrolled in any lessons yet.',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.25),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _lessons.length,
              itemBuilder: (context, index) {
                final lesson = _lessons[index];
                final title = (lesson['title'] ?? '').toString();
                final desc = (lesson['description'] ?? '').toString();

                return AppleCard(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child:
                            Icon(Icons.book, color: theme.colorScheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            ),
                            if (desc.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                desc,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.70),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: theme.colorScheme.onSurface.withOpacity(0.45),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
