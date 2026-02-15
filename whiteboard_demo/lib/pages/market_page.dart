import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../theme_provider.dart';
import '../providers/developer_mode_provider.dart';
import '../services/auth_service.dart';
import 'home.dart';
import 'profile_page.dart';

class MarketPage extends StatefulWidget {
  const MarketPage({super.key});

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  List<dynamic> listings = [];
  bool isLoading = true;
  String? errorMessage;

  final String baseUrl = "${dotenv.env['API_URL']}/api/market/listings/";

  @override
  void initState() {
    super.initState();
    _fetchListings();
  }

  Future<void> _fetchListings() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final apiBase = (dotenv.env['API_URL'] ?? 'http://127.0.0.1:8000').trim();
      final authService = AuthService(baseUrl: apiBase);
      authService.onSessionExpired = () {
        if (mounted) Navigator.of(context).pushReplacementNamed('/login');
      };

      final response = await authService.authenticatedGet(baseUrl);

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() {
          listings = jsonDecode(response.body);
        });
      } else {
        setState(() {
          errorMessage = 'Failed to load market listings';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'Could not connect to server';
      });
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _buyItem(int listingId) async {
    final apiBase = (dotenv.env['API_URL'] ?? 'http://127.0.0.1:8000').trim();
    final authService = AuthService(baseUrl: apiBase);

    await authService.authenticatedPost(
      "${dotenv.env['API_URL']}/api/market/listings/buy/$listingId/",
    );

    _fetchListings();
  }

  void _openBargainDialog(int listingId) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Make an Offer"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: "Proposed price"),
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.dispose();
              Navigator.pop(context);
            },
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            child: const Text("Send"),
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                final apiBase = (dotenv.env['API_URL'] ?? 'http://127.0.0.1:8000').trim();
                final authService = AuthService(baseUrl: apiBase);

                await authService.authenticatedPost(
                  "${dotenv.env['API_URL']}/api/market/proposals/create/",
                  body: jsonEncode({
                    "listing": listingId,
                    "proposed_price": int.parse(controller.text),
                  }),
                );
              }

              controller.dispose();
              if (!context.mounted) return;
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _logout() async {
    final devProvider = Provider.of<DeveloperModeProvider>(context, listen: false);
    await devProvider.clear();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('refresh_token');
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    final isDarkMode = themeProvider.isDarkMode;

    return Scaffold(
      drawer: _buildDrawer(theme),
      appBar: AppBar(
        title: const Text("Market"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(isDarkMode ? Icons.dark_mode : Icons.light_mode),
            onPressed: themeProvider.toggleTheme,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(
                  child: Text(
                    errorMessage!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                )
              : listings.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.storefront_outlined,
                            size: 64,
                            color: theme.colorScheme.primary.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No listings available',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Check back later for new items',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.4),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: listings.length,
                      itemBuilder: (_, index) {
                        final item = listings[index];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          elevation: 3,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['item_name'],
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text("Seller: ${item['seller_username']}"),
                                Text(
                                  "Price: ${item['price']} credits",
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () => _buyItem(item['id']),
                                        child: const Text("BUY"),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () =>
                                            _openBargainDialog(item['id']),
                                        child: const Text("BARGAIN"),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
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
                        "DrawnOut",
                        style: TextStyle(
                            fontSize: 24, color: theme.colorScheme.primary),
                      ),
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
          ListTile(
            leading:
                Icon(Icons.home_outlined, color: theme.colorScheme.primary),
            title: const Text("Home"),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const HomePage()),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.menu_book, color: theme.colorScheme.primary),
            title: const Text("All Lessons"),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/lessons');
            },
          ),
          ListTile(
            leading:
                Icon(Icons.storefront, color: theme.colorScheme.primary),
            title: const Text("Market"),
            selected: true,
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading:
                Icon(Icons.draw_outlined, color: theme.colorScheme.primary),
            title: const Text("Whiteboard"),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/whiteboard');
            },
          ),
          ListTile(
            leading:
                Icon(Icons.person_outline, color: theme.colorScheme.primary),
            title: const Text("Profile"),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
            },
          ),
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
              subtitle: Text("Debug features enabled", style: TextStyle(fontSize: 11)),
            ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.primary),
            title: const Text("Logout"),
            onTap: _logout,
          ),
        ],
      ),
    );
  }
}
