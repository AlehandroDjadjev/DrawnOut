import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../theme_provider.dart';
import '../providers/developer_mode_provider.dart';
import 'home.dart';
import 'profile_page.dart';
import 'owned_items.dart';
import 'negotiations_page.dart';

class MarketPage extends StatefulWidget {
  const MarketPage({super.key});

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  List<dynamic> listings = [];
  bool isLoading = true;
  String? errorMessage;
  String? _currentUsername;
  Map<String, dynamic>? _profile;

  final String baseUrl = "${dotenv.env['API_URL']}/api/market/listings/";

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _fetchListings();
    _fetchProfile();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _currentUsername = prefs.getString('username'));
  }

  Future<void> _fetchListings() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        setState(() {
          errorMessage = 'You are not logged in';
          isLoading = false;
        });
        return;
      }

      final response = await http.get(
        Uri.parse(baseUrl),
        headers: {'Authorization': 'Bearer $token'},
      );

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

  Future<void> _buyItem(int listingId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;

    setState(() => isLoading = true);
    try {
      final resp = await http.post(
        Uri.parse(
            "${dotenv.env['API_URL']}/api/market/listings/buy/$listingId/"),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Purchase successful')));
      } else {
        final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        final msg = (body is Map && body['error'] != null)
            ? body['error']
            : 'Purchase failed';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg.toString())));
      }
    } catch (_) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Network error')));
    } finally {
      await _fetchListings();
      if (mounted) setState(() => isLoading = false);
    }
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
              final prefs = await SharedPreferences.getInstance();
              final token = prefs.getString('token');

              if (token != null && controller.text.trim().isNotEmpty) {
                try {
                  final resp = await http.post(
                    Uri.parse(
                        "${dotenv.env['API_URL']}/api/market/trade-proposals/create/"),
                    headers: {
                      'Authorization': 'Bearer $token',
                      'Content-Type': 'application/json',
                    },
                    body: jsonEncode({
                      "listing": listingId,
                      "proposed_price": int.parse(controller.text),
                    }),
                  );
                  if (resp.statusCode == 201 || resp.statusCode == 200) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Offer sent')));
                    _fetchListings();
                  } else {
                    final body =
                        resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
                    final msg = (body is Map && body['detail'] != null)
                        ? body['detail']
                        : 'Failed to send offer';
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(msg.toString())));
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Network error')));
                }
              }

              controller.dispose();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  Future<void> _viewOffersDialog(int listingId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;

    final url =
        '${dotenv.env['API_URL']}/api/market/listings/$listingId/proposals/';
    try {
      final resp = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
      if (resp.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load offers')));
        return;
      }
      final list = jsonDecode(resp.body) as List<dynamic>;

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Offers'),
          content: SizedBox(
            width: 400,
            child: list.isEmpty
                ? const Text('No offers yet')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final p = list[i];
                      return ListTile(
                        title: Text(
                            '${p['buyer_username'] ?? 'User'} offered ${p['proposed_price']} (counters: ${p['counters']?.length ?? 0})'),
                        subtitle: Text('Status: ${p['status']}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon:
                                  const Icon(Icons.check, color: Colors.green),
                              onPressed: p['status'] == 'pending'
                                  ? () => _respondToOffer(p['id'], accept: true)
                                  : null,
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: p['status'] == 'pending'
                                  ? () =>
                                      _respondToOffer(p['id'], accept: false)
                                  : null,
                            ),
                            IconButton(
                              icon: const Icon(Icons.compare_arrows,
                                  color: Colors.orange),
                              onPressed: p['status'] == 'pending'
                                  ? () => _openCounterDialog(p['id'])
                                  : null,
                            ),
                          ],
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
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Error loading offers')));
    }
  }

  void _openCounterDialog(int proposalId) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Counter Offer'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Counter price'),
        ),
        actions: [
          TextButton(
              onPressed: () {
                controller.dispose();
                Navigator.pop(context);
              },
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                final token = prefs.getString('token');
                if (token == null) return;
                final url =
                    '${dotenv.env['API_URL']}/api/market/counter-offers/create/';
                try {
                  final resp = await http.post(Uri.parse(url),
                      headers: {
                        'Authorization': 'Bearer $token',
                        'Content-Type': 'application/json'
                      },
                      body: jsonEncode({
                        'original_proposal': proposalId,
                        'price': int.parse(controller.text)
                      }));
                  if (resp.statusCode == 201 || resp.statusCode == 200) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Counter sent')));
                    Navigator.pop(context);
                    _fetchListings();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Failed to send counter')));
                  }
                } catch (_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Network error')));
                }
                controller.dispose();
              },
              child: const Text('Send')),
        ],
      ),
    );
  }

  Future<void> _respondToOffer(int proposalId, {required bool accept}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;

    final url =
        '${dotenv.env['API_URL']}/api/market/trade-proposals/${accept ? 'accept' : 'decline'}/$proposalId/';
    try {
      final resp = await http
          .post(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(accept ? 'Offer accepted' : 'Offer declined')));
        Navigator.pop(context); // close offers dialog
        _fetchListings();
      } else {
        final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        final msg = (body is Map && body['error'] != null)
            ? body['error']
            : 'Failed to respond';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg.toString())));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Network error')));
    }
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
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Check back later for new items',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.4),
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
                                  "Price: ${item['price']} credits • Left listed: ${item['quantity'] ?? 1} • Total stock: ${item['item_stock'] ?? 'N/A'}",
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
                                        onPressed:
                                            (item['seller_username'] != null &&
                                                    item['seller_username'] ==
                                                        _currentUsername)
                                                ? null
                                                : () => _buyItem(item['id']),
                                        child: const Text("BUY"),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: (item['item_stock'] !=
                                                    null &&
                                                (item['item_stock'] as int) <=
                                                    0)
                                            ? null
                                            : ((item['seller_username'] !=
                                                        null &&
                                                    item['seller_username'] ==
                                                        _currentUsername)
                                                ? null
                                                : () => _openBargainDialog(
                                                    item['id'])),
                                        child: const Text("BARGAIN"),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // If current user is the seller, show 'View Offers' button
                                if (item['seller_username'] != null &&
                                    item['seller_username'] == _currentUsername)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () =>
                                          _viewOffersDialog(item['id']),
                                      child: const Text('View Offers'),
                                    ),
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
              child: GestureDetector(
                onTap: () {
                  final toggled = devMode.handleSecretTap();
                  if (toggled) {
                    Navigator.pop(context);
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
            leading: Icon(Icons.storefront, color: theme.colorScheme.primary),
            title: const Text("Market"),
            selected: true,
            onTap: () {
              Navigator.pop(context);
            },
          ),
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
