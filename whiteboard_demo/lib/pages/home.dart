import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../theme_provider.dart';
import '../ui/apple_ui.dart';
import '../providers/developer_mode_provider.dart';
import '../services/auth_service.dart';
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

  String get _apiBase =>
      (dotenv.env['API_URL'] ?? 'http://127.0.0.1:8000').trim();

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    try {
      final authService = AuthService(baseUrl: _apiBase);
      final url = '$_apiBase/api/auth/profile/';
      final resp = await authService.authenticatedGet(url);
      if (resp.statusCode == 200) {
        final map = jsonDecode(resp.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() => _profile = map);
      }
    } catch (_) {}
  }

  Future<void> _fetchNotifications() async {
    try {
      final authService = AuthService(baseUrl: _apiBase);
      final url = '$_apiBase/api/market/notifications/';
      final resp = await authService.authenticatedGet(url);
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
      final authService = AuthService(baseUrl: _apiBase);
      final url = '$_apiBase/api/market/notifications/read/$id/';
      final resp = await authService.authenticatedPost(url);
      if (resp.statusCode == 200) {
        await _fetchNotifications();
      }
    } catch (_) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Network error')));
    }
  }

  Future<void> _markAllNotificationsRead() async {
    try {
      final authService = AuthService(baseUrl: _apiBase);
      final url = '$_apiBase/api/market/notifications/read-all/';
      final resp = await authService.authenticatedPost(url);
      if (resp.statusCode == 200) {
        await _fetchNotifications();
      }
    } catch (_) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Network error')));
    }
  }

  void _logout() async {
    // Clear developer mode
    final devProvider =
        Provider.of<DeveloperModeProvider>(context, listen: false);
    await devProvider.clear();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('refresh_token');
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
                      title: Row(
                        children: [
                          const Expanded(child: Text('Notifications')),
                          if (_unreadCount > 0)
                            TextButton(
                              onPressed: () async {
                                Navigator.pop(context);
                                await _markAllNotificationsRead();
                              },
                              child: const Text('Mark all read'),
                            ),
                        ],
                      ),
                      content: SizedBox(
                        width: 400,
                        child: _notifications.isEmpty
                            ? const Text('No notifications')
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: _notifications.length,
                                itemBuilder: (_, i) {
                                  final n = _notifications[i];
                                  final proposalId =
                                      n['proposal_id'] is int ? n['proposal_id'] as int : null;
                                  final itemName = n['item_name']?.toString();
                                  return ListTile(
                                    leading: Icon(
                                      n['is_read'] == false
                                          ? Icons.markunread
                                          : Icons.notifications_none,
                                      size: 20,
                                    ),
                                    title: Text(n['verb'] ?? ''),
                                    subtitle: Text(itemName == null
                                        ? (n['created_at'] ?? '')
                                        : '$itemName • ${n['created_at'] ?? ''}'),
                                    trailing: TextButton(
                                      onPressed: () async {
                                        Navigator.pop(context);
                                        if (n['is_read'] == false) {
                                          await _markNotificationRead(n['id']);
                                        }
                                        if (proposalId != null && mounted) {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => NegotiationsPage(
                                                highlightProposalId: proposalId,
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                      child: Text(
                                        proposalId != null ? 'Open' : 'Read',
                                      ),
                                    ),
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
      body: AppleBackground(child: pages[_selectedIndex]),
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
                              fontSize: 18, color: theme.colorScheme.primary)),
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

          // Lessons
          ListTile(
            leading: Icon(Icons.menu_book, color: theme.colorScheme.primary),
            title: const Text("All Lessons"),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/lessons');
            },
          ),

          // History
          ListTile(
            leading: Icon(Icons.history, color: theme.colorScheme.primary),
            title: const Text('Lesson History'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/history');
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

          // Developer mode indicator (controlled via database)
          if (devMode.isEnabled)
            const ListTile(
              leading: Icon(Icons.developer_mode, color: Colors.orange),
              title: Text("Developer Account"),
              subtitle: Text("Debug features enabled",
                  style: TextStyle(fontSize: 11)),
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
    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 720;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppleHeader(
                title: 'Welcome',
                subtitle:
                    'Learn, interact, and practice with your AI tutor. Start with a quick lesson or jump into the whiteboard.',
              ),
              const SizedBox(height: 16),
              isWide
                  ? Row(
                      children: [
                        Expanded(
                          child: _QuickActionCard(
                            icon: Icons.menu_book,
                            title: 'Lessons',
                            subtitle: 'Browse all lessons',
                            onTap: () =>
                                Navigator.pushNamed(context, '/lessons'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _QuickActionCard(
                            icon: Icons.storefront_outlined,
                            title: 'Market',
                            subtitle: 'Explore the marketplace',
                            onTap: () =>
                                Navigator.pushNamed(context, '/market'),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _QuickActionCard(
                          icon: Icons.menu_book,
                          title: 'Lessons',
                          subtitle: 'Browse all lessons',
                          onTap: () => Navigator.pushNamed(context, '/lessons'),
                        ),
                        const SizedBox(height: 12),
                        _QuickActionCard(
                          icon: Icons.storefront_outlined,
                          title: 'Market',
                          subtitle: 'Explore the marketplace',
                          onTap: () => Navigator.pushNamed(context, '/market'),
                        ),
                      ],
                    ),
              const SizedBox(height: 12),
              _QuickActionCard(
                icon: Icons.draw_outlined,
                title: 'Whiteboard',
                subtitle: 'Practice and explore',
                onTap: () => Navigator.pushNamed(context, '/whiteboard'),
              ),
              const SizedBox(height: 20),
              const AppleSectionTitle(title: 'Available lesson'),
              const SizedBox(height: 10),
              AppleCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pythagoras Theorem',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Explore the relationship between the sides of a right-angled triangle and understand one of the most fundamental theorems in mathematics.',
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.25),
                    ),
                    const SizedBox(height: 14),
                    ApplePrimaryButton(
                      label: 'Start lesson',
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          '/whiteboard',
                          arguments: {
                            'topic': 'Pythagorean Theorem',
                            'title': 'Pythagoras Theorem',
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppleCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: theme.colorScheme.primary),
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
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.70),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurface.withOpacity(0.45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
