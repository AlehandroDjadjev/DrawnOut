import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../theme_provider.dart';
import '../providers/developer_mode_provider.dart';
import 'profile_page.dart';
import 'owned_items.dart';
import 'negotiations_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<dynamic> _notifications = [];
  int _unreadCount = 0;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;
      final base = dotenv.env['API_URL'] ?? '';
      final url = '$base/api/auth/profile/';
      final resp = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
      if (resp.statusCode == 200) {
        final map = jsonDecode(resp.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() => _profile = map);
      }
    } catch (_) {}
  }

  Future<void> _fetchNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;
      final base = dotenv.env['API_URL'] ?? '';
      final url = '$base/api/market/notifications/';
      final resp = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        if (!mounted) return;
        setState(() {
          _notifications = list;
          _unreadCount = list.where((n) => n['is_read'] == false).length;
        });
      }
    } catch (_) {}
  }

  Future<void> _markNotificationRead(int id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;
      final base = dotenv.env['API_URL'] ?? '';
      final url = '$base/api/market/notifications/read/$id/';
      final resp = await http
          .post(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Marked as read')));
        await _fetchNotifications();
      }
    } catch (_) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Network error')));
    }
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = context.watch<ThemeProvider>().isDarkMode;
    final themeProvider = context.read<ThemeProvider>();

    final List<Widget> pages = [
      _buildHomeContent(theme),
      const ProfilePage(),
    ];

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(theme),
      appBar: AppBar(
        title: Text(_selectedIndex == 0 ? 'Home' : 'Profile'),
        centerTitle: true,
        actions: [
          // Notification bell
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none),
                onPressed: () {
                  // show notifications dialog
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Notifications'),
                      content: SizedBox(
                        width: 400,
                        child: _notifications.isEmpty
                            ? const Text('No notifications')
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: _notifications.length,
                                itemBuilder: (_, i) {
                                  final n = _notifications[i];
                                  return ListTile(
                                    title: Text(n['verb'] ?? ''),
                                    subtitle: Text(n['created_at'] ?? ''),
                                    trailing: n['is_read'] == false
                                        ? TextButton(
                                            onPressed: () async {
                                              Navigator.pop(context);
                                              await _markNotificationRead(
                                                  n['id']);
                                            },
                                            child: const Text('Mark read'),
                                          )
                                        : TextButton(
                                            onPressed: () {
                                              Navigator.pop(context);
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                    builder: (_) =>
                                                        const NegotiationsPage()),
                                              );
                                            },
                                            child: const Text('Open')),
                                  );
                                },
                              ),
                      ),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close')),
                      ],
                    ),
                  );
                },
              ),
              if (_unreadCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: CircleAvatar(
                    radius: 8,
                    backgroundColor: Colors.red,
                    child: Text(
                      '$_unreadCount',
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, animation) {
              return RotationTransition(
                turns: Tween(begin: 0.75, end: 1.0).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: IconButton(
              key: ValueKey(isDarkMode),
              icon: Icon(isDarkMode ? Icons.dark_mode : Icons.light_mode),
              onPressed: themeProvider.toggleTheme,
            ),
          ),
        ],
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: theme.colorScheme.primary,
        unselectedItemColor: theme.colorScheme.onSurface.withOpacity(0.6),
        onTap: (index) => setState(() => _selectedIndex = index),
        items: [
          BottomNavigationBarItem(
            icon: _navIcon(Icons.home_outlined, 0, theme),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: _navIcon(Icons.person_outline_rounded, 1, theme),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _navIcon(
    IconData icon,
    int index,
    ThemeData theme,
  ) {
    final isSelected = _selectedIndex == index;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected
            ? theme.colorScheme.primary.withOpacity(0.2)
            : Colors.transparent,
      ),
      child: Icon(
        icon,
        color: isSelected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface.withOpacity(0.6),
      ),
    );
  }

  Widget _buildDrawer(ThemeData theme) {
    final devMode = Provider.of<DeveloperModeProvider>(context);

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
            ),
            child: Center(
              // Secret tap area to enable developer mode
              child: GestureDetector(
                onTap: () {
                  final toggled = devMode.handleSecretTap();
                  if (toggled) {
                    Navigator.pop(context); // Close drawer
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          devMode.isEnabled
                              ? 'Developer mode enabled'
                              : 'Developer mode disabled',
                        ),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.school,
                        size: 32, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            _profile != null
                                ? (_profile!['username'] ?? 'DrawnOut')
                                : 'DrawnOut',
                            style: TextStyle(
                                fontSize: 18,
                                color: theme.colorScheme.primary)),
                        const SizedBox(height: 6),
                        Text(
                            _profile != null
                                ? 'Credits: ${_profile!['credits']}'
                                : '',
                            style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.7))),
                        if (devMode.isEnabled)
                          Text(
                            "Developer Mode",
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.primary.withOpacity(0.7),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Lessons
          ListTile(
            leading: Icon(Icons.menu_book, color: theme.colorScheme.primary),
            title: const Text("All Lessons"),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/lessons');
            },
          ),

          // Market
          ListTile(
            leading: Icon(Icons.storefront_outlined,
                color: theme.colorScheme.primary),
            title: const Text('Market'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/market');
            },
          ),

          // Negotiations
          ListTile(
            leading: Icon(Icons.handshake, color: theme.colorScheme.primary),
            title: const Text('Negotiations'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NegotiationsPage()),
              );
            },
          ),

          // My Items
          ListTile(
            leading: Icon(Icons.inventory, color: theme.colorScheme.primary),
            title: const Text('My Items'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OwnedItemsPage()),
              );
            },
          ),

          // Whiteboard
          ListTile(
            leading:
                Icon(Icons.draw_outlined, color: theme.colorScheme.primary),
            title: const Text('Whiteboard'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/whiteboard');
            },
          ),

          // Settings
          ListTile(
            leading: Icon(Icons.settings, color: theme.colorScheme.primary),
            title: const Text("Settings"),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/settings');
            },
          ),

          // Developer mode controls
          if (devMode.isEnabled)
            ListTile(
              leading: const Icon(Icons.developer_mode, color: Colors.orange),
              title: const Text("Disable Dev Mode"),
              onTap: () {
                devMode.disable();
                Navigator.pop(context);
              },
            ),

          const Divider(),

          // Logout
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.primary),
            title: const Text("Logout"),
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  Widget _buildHomeContent(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.school,
                      size: 28,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Welcome to DrawnOut',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Learn, interact, and practice with your AI tutor.\n'
                  'Start with the demo lesson below!',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Available Lesson',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            margin: const EdgeInsets.symmetric(vertical: 10),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pythagoras Theorem',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Explore the relationship between the sides of a '
                    'right-angled triangle and understand one of the most '
                    'fundamental theorems in mathematics.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pushNamed(context, '/lessons');
                        },
                        icon: const Icon(Icons.menu_book, size: 18),
                        label: const Text("Browse All"),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                        onPressed: () {
                          Navigator.pushNamed(context, '/whiteboard');
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text(
                          "Start Lesson",
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
