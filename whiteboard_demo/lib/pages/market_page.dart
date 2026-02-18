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
  bool _isSubmitting = false;
  String? errorMessage;
  String? _currentUsername;
  Map<String, dynamic>? _profile;
  String _searchQuery = '';
  bool _showMineOnly = false;

  String get _apiBase =>
      (dotenv.env['API_URL'] ?? 'http://127.0.0.1:8000').trim();
  String get _listingsUrl => '$_apiBase/api/market/listings/';

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

  int _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _money(dynamic value) => _toDouble(value).toStringAsFixed(2);

  bool _isMine(dynamic listing) =>
      listing['seller_username']?.toString() == _currentUsername;

  String _readError(String body, String fallback) {
    if (body.isEmpty) return fallback;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['error'] != null) return decoded['error'].toString();
        if (decoded['detail'] != null) return decoded['detail'].toString();
        if (decoded['non_field_errors'] != null) {
          return decoded['non_field_errors'].toString();
        }
        if (decoded['quantity'] != null) return decoded['quantity'].toString();
        if (decoded['price'] != null) return decoded['price'].toString();
      }
    } catch (_) {}
    return fallback;
  }

  List<dynamic> get _visibleListings {
    final query = _searchQuery.trim().toLowerCase();
    return listings.where((item) {
      if (_showMineOnly && !_isMine(item)) return false;
      if (query.isEmpty) return true;
      final name = item['item_name']?.toString().toLowerCase() ?? '';
      final seller = item['seller_username']?.toString().toLowerCase() ?? '';
      return name.contains(query) || seller.contains(query);
    }).toList();
  }

  Future<void> _fetchListings() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final authService = AuthService(baseUrl: _apiBase);
      authService.onSessionExpired = () {
        if (mounted) Navigator.of(context).pushReplacementNamed('/login');
      };

      final response = await authService.authenticatedGet(_listingsUrl);

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() {
          listings = jsonDecode(response.body);
        });
      } else {
        setState(() {
          errorMessage =
              _readError(response.body, 'Failed to load market listings');
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
      final apiBase = (dotenv.env['API_URL'] ?? 'http://127.0.0.1:8000').trim();
      final authService = AuthService(baseUrl: apiBase);
      final url = '$apiBase/api/auth/profile/';
      final resp = await authService.authenticatedGet(url);
      if (resp.statusCode == 200) {
        final map = jsonDecode(resp.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() => _profile = map);
      }
    } catch (_) {}
  }

  Future<void> _buyItem(int listingId, int quantity) async {
    final authService = AuthService(baseUrl: _apiBase);
    setState(() => _isSubmitting = true);
    try {
      final resp = await authService.authenticatedPost(
        '$_apiBase/api/market/listings/buy/$listingId/',
        body: jsonEncode({'quantity': quantity}),
      );
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Purchase successful ($quantity item${quantity == 1 ? '' : 's'})'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_readError(resp.body, 'Purchase failed'))),
        );
      }
    } catch (_) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Network error')));
    } finally {
      await _fetchListings();
      await _fetchProfile();
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _openBuyDialog(dynamic item) async {
    final maxQty = _toInt(item['quantity']);
    final qtyController = TextEditingController(text: '1');

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Buy ${item['item_name'] ?? 'Item'}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Price: ${_money(item['price'])} credits each'),
            Text('Available: $maxQty'),
            const SizedBox(height: 12),
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final qty = int.tryParse(qtyController.text.trim());
              if (qty == null || qty <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter a valid quantity')),
                );
                return;
              }
              if (qty > maxQty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Only $maxQty item(s) available')),
                );
                return;
              }
              Navigator.pop(dialogContext);
              await _buyItem(item['id'], qty);
            },
            child: const Text('Buy'),
          ),
        ],
      ),
    );

    qtyController.dispose();
  }

  Future<void> _cancelListing(int listingId) async {
    final authService = AuthService(baseUrl: _apiBase);
    setState(() => _isSubmitting = true);
    try {
      final resp = await authService.authenticatedPost(
        '$_apiBase/api/market/listings/cancel/$listingId/',
      );
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Listing cancelled')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_readError(resp.body, 'Failed to cancel listing'))),
        );
      }
    } catch (_) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Network error')));
    } finally {
      await _fetchListings();
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _openBargainDialog(dynamic listing) {
    final controller = TextEditingController(text: _money(listing['price']));

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Make an Offer"),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                final authService = AuthService(baseUrl: _apiBase);

                try {
                  final offered = double.tryParse(controller.text.trim());
                  if (offered == null || offered <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Enter a valid offer price')),
                    );
                    return;
                  }
                  final resp = await authService.authenticatedPost(
                    '$_apiBase/api/market/trade-proposals/create/',
                    body: jsonEncode({
                      "listing": listing['id'],
                      "proposed_price": offered.toStringAsFixed(2),
                    }),
                  );
                  if (resp.statusCode == 201 || resp.statusCode == 200) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Offer sent')));
                    _fetchListings();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            _readError(resp.body, 'Failed to send offer'))));
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Network error')));
                }
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
    final devProvider =
        Provider.of<DeveloperModeProvider>(context, listen: false);
    await devProvider.clear();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('refresh_token');
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  Future<void> _viewOffersDialog(int listingId) async {
    final authService = AuthService(baseUrl: _apiBase);

    final url = '$_apiBase/api/market/listings/$listingId/proposals/';
    try {
      final resp = await authService.authenticatedGet(url);
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
                                  ? () => _openCounterDialog(
                                        p['id'],
                                        suggestedPrice:
                                            p['proposed_price']?.toString(),
                                      )
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

  void _openCounterDialog(int proposalId, {String? suggestedPrice}) {
    final controller = TextEditingController(text: suggestedPrice ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Counter Offer'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                final authService = AuthService(baseUrl: _apiBase);
                final url = '$_apiBase/api/market/counter-offers/create/';
                try {
                  final price = double.tryParse(controller.text.trim());
                  if (price == null || price <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Enter a valid counter price')),
                    );
                    return;
                  }
                  final resp = await authService.authenticatedPost(url,
                      body: jsonEncode({
                        'original_proposal': proposalId,
                        'price': price.toStringAsFixed(2),
                      }));
                  if (resp.statusCode == 201 || resp.statusCode == 200) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Counter sent')));
                    Navigator.pop(context);
                    _fetchListings();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              _readError(resp.body, 'Failed to send counter'))),
                    );
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
    final authService = AuthService(baseUrl: _apiBase);

    final url =
        '$_apiBase/api/market/trade-proposals/${accept ? 'accept' : 'decline'}/$proposalId/';
    try {
      final resp = await authService.authenticatedPost(url);
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(accept ? 'Offer accepted' : 'Offer declined')));
        Navigator.pop(context); // close offers dialog
        _fetchListings();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_readError(resp.body, 'Failed to respond'))));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Network error')));
    }
  }

  Widget _buildDrawer(ThemeData theme) {
    final devMode = Provider.of<DeveloperModeProvider>(context);

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.06)),
            child: Row(
              children: [
                Icon(Icons.school, size: 34, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
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
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.7))),
                    if (devMode.isEnabled)
                      Text('Developer Mode',
                          style: TextStyle(
                              fontSize: 10,
                              color:
                                  theme.colorScheme.primary.withOpacity(0.7))),
                  ],
                ),
              ],
            ),
          ),
          ListTile(
              leading:
                  Icon(Icons.home_outlined, color: theme.colorScheme.primary),
              title: const Text('Home'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const HomePage()));
              }),
          ListTile(
              leading: Icon(Icons.menu_book, color: theme.colorScheme.primary),
              title: const Text('All Lessons'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/lessons');
              }),
          ListTile(
              leading: Icon(Icons.storefront, color: theme.colorScheme.primary),
              title: const Text('Market'),
              selected: true,
              onTap: () {
                Navigator.pop(context);
              }),
          ListTile(
              leading: Icon(Icons.inventory, color: theme.colorScheme.primary),
              title: const Text('My Items'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const OwnedItemsPage()));
              }),
          ListTile(
              leading: Icon(Icons.handshake, color: theme.colorScheme.primary),
              title: const Text('Negotiations'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NegotiationsPage()));
              }),
          ListTile(
              leading:
                  Icon(Icons.person_outline, color: theme.colorScheme.primary),
              title: const Text('Profile'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ProfilePage()));
              }),
          ListTile(
              leading: Icon(Icons.settings, color: theme.colorScheme.primary),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/settings');
              }),
          if (devMode.isEnabled)
            const ListTile(
                leading: Icon(Icons.developer_mode, color: Colors.orange),
                title: Text('Developer Account'),
                subtitle: Text('Debug features enabled',
                    style: TextStyle(fontSize: 11))),
          const Divider(),
          ListTile(
              leading: Icon(Icons.logout, color: theme.colorScheme.primary),
              title: const Text('Logout'),
              onTap: _logout),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    final isDarkMode = themeProvider.isDarkMode;

    // consistent centered layout
    Widget content = isLoading
        ? const Center(child: CircularProgressIndicator())
        : errorMessage != null
            ? Center(
                child: Text(
                  errorMessage!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              )
            : _visibleListings.isEmpty
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
                          _showMineOnly
                              ? 'No active listings from you'
                              : 'No listings available',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _showMineOnly
                              ? 'Use "My Items" to list items first'
                              : 'Check back later for new items',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _visibleListings.length + 1,
                    itemBuilder: (_, index) {
                      if (index == 0) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                TextField(
                                  onChanged: (value) =>
                                      setState(() => _searchQuery = value),
                                  decoration: InputDecoration(
                                    hintText: 'Search item or seller',
                                    prefixIcon: const Icon(Icons.search),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    DropdownButton<String>(
                                      value: _showMineOnly ? 'mine' : 'all',
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'all', child: Text('All')),
                                        DropdownMenuItem(
                                            value: 'mine',
                                            child: Text('My Listings')),
                                      ],
                                      onChanged: (v) => setState(
                                          () => _showMineOnly = (v == 'mine')),
                                    ),
                                    Expanded(child: Container()),
                                    TextButton.icon(
                                        onPressed: _fetchListings,
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('Refresh')),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      final item = _visibleListings[index - 1];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['item_name'] ?? 'Unnamed',
                                  style: theme.textTheme.titleLarge),
                              const SizedBox(height: 8),
                              Text('Seller: ${item['seller_username'] ?? ''}'),
                              const SizedBox(height: 6),
                              Text(
                                  'Price: ${item['price']} credits  •  Left: ${item['quantity'] ?? 1}',
                                  style: TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              Row(children: [
                                Expanded(
                                    child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8))),
                                        onPressed:
                                            (_isMine(item) || _isSubmitting)
                                                ? null
                                                : () => _openBuyDialog(item),
                                        child: const Text('BUY'))),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8))),
                                        onPressed: (_isMine(item) ||
                                                _isSubmitting)
                                            ? null
                                            : () => _openBargainDialog(item),
                                        child: const Text('MAKE OFFER'))),
                              ]),
                              const SizedBox(height: 8),
                              if (_isMine(item))
                                Align(
                                    alignment: Alignment.centerRight,
                                    child: Wrap(spacing: 8, children: [
                                      TextButton(
                                          onPressed: _isSubmitting
                                              ? null
                                              : () =>
                                                  _viewOffersDialog(item['id']),
                                          child: const Text('View Offers')),
                                      OutlinedButton(
                                          onPressed: _isSubmitting
                                              ? null
                                              : () =>
                                                  _cancelListing(item['id']),
                                          child: const Text('Cancel Listing'))
                                    ]))
                            ],
                          ),
                        ),
                      );
                    },
                  );

    return Scaffold(
      drawer: _buildDrawer(theme),
      appBar: AppBar(
        title: const Text('Market'),
        centerTitle: true,
        actions: [
          if (_profile != null)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                    child: Text('Credits: ${_profile!['credits']}',
                        style: const TextStyle(fontWeight: FontWeight.w600)))),
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: _fetchListings),
          IconButton(
              icon: Icon(isDarkMode ? Icons.dark_mode : Icons.light_mode),
              onPressed: themeProvider.toggleTheme),
        ],
      ),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: content)),
    );
  }
}
