import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _userData;
  List<dynamic> _lessons = [];
  bool _isLoading = true;
  String? _errorMessage;

  final String baseUrl = 'http://192.168.7.7:8000/api/';

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

      // Fetch user profile
      final userResponse = await http.get(
        Uri.parse('${baseUrl}auth/profile/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      // Fetch lessons
      final lessonsResponse = await http.get(
        Uri.parse('${baseUrl}lessons/list/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (userResponse.statusCode == 200 && lessonsResponse.statusCode == 200) {
        setState(() {
          _userData = jsonDecode(userResponse.body);
          _lessons = jsonDecode(lessonsResponse.body);
        });
      } else {
        setState(() {
          _errorMessage =
              'Failed to fetch profile or lessons: ${userResponse.statusCode}, ${lessonsResponse.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not connect to server';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 16),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Card(
                    elevation: 6,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: CircleAvatar(
                              radius: 50,
                              backgroundImage: _userData?['pfp'] != null
                                  ? NetworkImage(_userData!['pfp'])
                                  : const AssetImage(
                                          'assets/default_avatar.png')
                                      as ImageProvider,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Center(
                            child: Text(
                              _userData?['username'] ?? 'Username',
                              style: const TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              _userData?['email'] ?? 'Email',
                              style: const TextStyle(
                                  fontSize: 16, color: Colors.grey),
                            ),
                          ),
                          const Divider(height: 32, thickness: 1),
                          const Text(
                            'Your Lessons',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          if (_lessons.isEmpty)
                            const Center(
                                child: Text(
                                    'You are not enrolled in any lessons yet.'))
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _lessons.length,
                              itemBuilder: (context, index) {
                                final lesson = _lessons[index];
                                return Card(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: ListTile(
                                    title: Text(lesson['title']),
                                    subtitle: Text(lesson['description'] ?? ''),
                                    trailing: const Icon(
                                        Icons.arrow_forward_ios,
                                        size: 16),
                                    onTap: () {
                                      // Navigate to lesson detail if needed
                                    },
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }
}
