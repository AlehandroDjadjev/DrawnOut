import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:shared_preferences/shared_preferences.dart';
import '../theme_provider/theme_provider.dart';
import '../ui/apple_ui.dart';
import 'profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

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
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.school,
                    size: 32,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'DrawnOut',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.primary,
                    ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Market
          ListTile(
            leading: Icon(
              Icons.storefront_outlined,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Market'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/market');
            },
          ),

          // Whiteboard
          ListTile(
            leading: Icon(
              Icons.draw_outlined,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Whiteboard'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/whiteboard');
            },
          ),

          const Divider(),

          // Logout
          ListTile(
            leading: Icon(
              Icons.logout,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Logout'),
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
                            icon: Icons.storefront_outlined,
                            title: 'Market',
                            subtitle: 'Buy cosmetics',
                            onTap: () => Navigator.pushNamed(context, '/market'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _QuickActionCard(
                            icon: Icons.draw_outlined,
                            title: 'Whiteboard',
                            subtitle: 'Practice and explore',
                            onTap: () =>
                                Navigator.pushNamed(context, '/whiteboard'),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _QuickActionCard(
                          icon: Icons.storefront_outlined,
                          title: 'Market',
                          subtitle: 'Browse available lessons',
                          onTap: () => Navigator.pushNamed(context, '/market'),
                        ),
                        const SizedBox(height: 12),
                        _QuickActionCard(
                          icon: Icons.draw_outlined,
                          title: 'Whiteboard',
                          subtitle: 'Practice and explore',
                          onTap: () =>
                              Navigator.pushNamed(context, '/whiteboard'),
                        ),
                      ],
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
                        Navigator.pushNamed(context, '/whiteboard');
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
                          color:
                              theme.colorScheme.onSurface.withOpacity(0.70),
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
