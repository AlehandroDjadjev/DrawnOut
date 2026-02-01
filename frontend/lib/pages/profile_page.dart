import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import '../theme_provider/theme_provider.dart';
import 'edit_username_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _userData;
  List<dynamic> _lessons = [];
  bool _isLoading = true;
  String? _errorMessage;

  final String baseUrl = "${dotenv.env['API_URL']}/api/";

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

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        setState(() {
          _errorMessage = 'You are not logged in';
          _isLoading = false;
        });
        return;
      }

      final userResponse = await http.get(
        Uri.parse('${baseUrl}auth/profile/'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      final lessonsResponse = await http.get(
        Uri.parse('${baseUrl}lessons/list/'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (!mounted) return;

      if (userResponse.statusCode == 200 && lessonsResponse.statusCode == 200) {
        setState(() {
          _userData = jsonDecode(userResponse.body);
          _lessons = jsonDecode(lessonsResponse.body);
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to load profile data';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not connect to server';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _navigateToEditUsername() async {
    if (_userData == null) return;

    final updated = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            EditUsernamePage(currentUsername: _userData!['username']),
      ),
    );

    if (updated == true) {
      _fetchProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = context.watch<ThemeProvider>().isDarkMode;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Text(
          _errorMessage!,
          style: TextStyle(
            color: theme.colorScheme.error,
            fontSize: 16,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // Header
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDarkMode
                        ? const [
                            Color(0xFF0F2027),
                            Color(0xFF203A43),
                            Color(0xFF2C5364),
                          ]
                        : const [
                            Color(0xFF6DD5FA),
                            Color(0xFF2980B9),
                          ],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(60),
                    bottomRight: Radius.circular(60),
                  ),
                ),
              ),
              Positioned(
                bottom: -60,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 4,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 60,
                      backgroundImage: _userData?['pfp'] != null
                          ? NetworkImage(_userData!['pfp'])
                          : const AssetImage('assets/default_avatar.png')
                              as ImageProvider,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 70),

          // Username + name + edit
          Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                children: [
                  Text(
                    _userData?['username'] ?? '',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${_userData?['first_name'] ?? ''} ${_userData?['last_name'] ?? ''}",
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _userData?['email'] ?? '',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
              Positioned(
                right: -8,
                top: -8,
                child: IconButton(
                  onPressed: _navigateToEditUsername,
                  icon: const Icon(Icons.edit, size: 20),
                  tooltip: 'Edit Username',
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),

          Text(
            "Your Lessons",
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 12),

          if (_lessons.isEmpty)
            const Text(
              "You are not enrolled in any lessons yet.",
              style: TextStyle(fontSize: 16),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _lessons.length,
              itemBuilder: (context, index) {
                final lesson = _lessons[index];
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  elevation: 3,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          theme.colorScheme.primary.withOpacity(0.1),
                      child: Icon(
                        Icons.book,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    title: Text(lesson['title']),
                    subtitle: Text(lesson['description'] ?? ''),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
