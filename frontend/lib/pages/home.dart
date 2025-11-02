import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import 'profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _logout() async {
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final theme = Theme.of(context);

    final List<Widget> _pages = [
      _buildHomeContent(theme, isDarkMode),
      ProfilePage(),
    ];

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(theme),
      appBar: AppBar(
        title: const Text("Home"),
        centerTitle: true,
        backgroundColor: isDarkMode ? Colors.black : Colors.white,
        foregroundColor: theme.colorScheme.primary,
        elevation: 1,
        iconTheme: IconThemeData(color: theme.colorScheme.primary),
        actions: [
          IconButton(
            icon: Icon(isDarkMode ? Icons.dark_mode : Icons.light_mode),
            onPressed: themeProvider.toggleTheme,
          ),
        ],
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        backgroundColor: isDarkMode ? Colors.black : Colors.white,
        selectedItemColor: theme.colorScheme.primary,
        unselectedItemColor: isDarkMode ? Colors.grey[400] : Colors.grey[600],
        onTap: (index) => setState(() => _selectedIndex = index),
        items: [
          BottomNavigationBarItem(
            icon: _navIcon(Icons.home_outlined, 0, theme, isDarkMode),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: _navIcon(Icons.person_outline_rounded, 1, theme, isDarkMode),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _navIcon(IconData icon, int index, ThemeData theme, bool isDarkMode) {
    final bool isSelected = _selectedIndex == index;
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
            : (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
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
                color: theme.colorScheme.primary.withOpacity(0.1)),
            child: Center(
              child: Text("AI Tutor",
                  style: TextStyle(
                      fontSize: 24, color: theme.colorScheme.primary)),
            ),
          ),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.primary),
            title: const Text("Logout"),
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  Widget _buildHomeContent(ThemeData theme, bool isDarkMode) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.teal.shade700 : Colors.blue.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome to AI Tutor 🎓',
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                SizedBox(height: 10),
                Text(
                    'Learn, interact, and practice with your AI tutor.\nStart with the demo lesson below!',
                    style: TextStyle(fontSize: 16)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Available Lesson',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color:
                    isDarkMode ? Colors.tealAccent.shade100 : Colors.grey[800]),
          ),
          const SizedBox(height: 12),
          Card(
            color: isDarkMode ? Colors.grey[900] : Colors.white,
            elevation: 5,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: const EdgeInsets.symmetric(vertical: 10),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pythagoras’ Theorem',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    'Explore the relationship between the sides of a right-angled triangle and understand one of the most fundamental theorems in mathematics.',
                    style: TextStyle(
                        fontSize: 16,
                        color:
                            isDarkMode ? Colors.grey[300] : Colors.grey[700]),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                      onPressed: () {},
                      icon: const Icon(Icons.play_arrow),
                      label: const Text("Start Lesson",
                          style: TextStyle(fontSize: 16)),
                    ),
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
