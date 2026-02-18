import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../ui/apple_ui.dart';
import '../theme_provider.dart';

class OwnedItemsPage extends StatefulWidget {
  const OwnedItemsPage({super.key});

  @override
  State<OwnedItemsPage> createState() => _OwnedItemsPageState();
}

class _OwnedItemsPageState extends State<OwnedItemsPage> {
  List<dynamic> _items = [];
  bool _loading = true;
  bool _submitting = false;
  String? _errorMessage;
  Map<String, dynamic>? _profile;

  late final AuthService _authService;

  String get _apiBase =>
      (dotenv.env['API_URL'] ?? 'http://127.0.0.1:8000').trim();

  @override
  void initState() {
    super.initState();
    _authService = AuthService(baseUrl: _apiBase);
    _authService.onSessionExpired = () {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
    };
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _fetchOwned(),
      _fetchProfile(),
    ]);
  }

  Future<void> _fetchProfile() async {
    try {
      final url = '$_apiBase/api/auth/profile/';
      final resp = await _authService.authenticatedGet(url);
      if (resp.statusCode != 200) return;
      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _profile = map);
    } catch (_) {}
  }

  Future<void> _fetchOwned() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final url = '$_apiBase/api/market/items/owned/';
      final resp = await _authService.authenticatedGet(url);

      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        if (!mounted) return;
        setState(() => _items = list);
      } else {
        if (!mounted) return;
        setState(() =>
            _errorMessage = _readError(resp.body, 'Failed to load items'));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Could not connect to the server');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _toMoney(dynamic value) {
    final asNum = num.tryParse(value?.toString() ?? '');
    if (asNum == null) return '0.00';
    return asNum.toStringAsFixed(2);
  }

  String _readError(String body, String fallback) {
    if (body.isEmpty) return fallback;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['error'] != null) return decoded['error'].toString();
        if (decoded['detail'] != null) return decoded['detail'].toString();
        if (decoded['quantity'] != null) return decoded['quantity'].toString();
        if (decoded['price'] != null) return decoded['price'].toString();
      }
    } catch (_) {}
    return fallback;
  }

  Future<void> _listItem({
    required int itemId,
    required int quantity,
    required double price,
  }) async {
    setState(() => _submitting = true);
    try {
      final url = '$_apiBase/api/market/items/$itemId/list/';
      final resp = await _authService.authenticatedPost(
        url,
        body: jsonEncode({
          'quantity': quantity,
          'price': price.toStringAsFixed(2),
        }),
      );

      if (!mounted) return;

      if (resp.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Listed $quantity item${quantity == 1 ? '' : 's'} at ${price.toStringAsFixed(2)} credits each',
            ),
          ),
        );
        await _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_readError(resp.body, 'Failed to list item'))),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network error')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openListDialog(Map<String, dynamic> item) async {
    final qtyOwned = _toInt(item['quantity']);
    final qtyController = TextEditingController(text: '1');
    final priceController =
        TextEditingController(text: _toMoney(item['item_price']));

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('List ${item['item_name'] ?? 'Item'}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Owned quantity: $qtyOwned'),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantity to list',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Price per item (credits)',
                ),
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
                final price = double.tryParse(priceController.text.trim());

                if (qty == null || qty <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter a valid quantity')),
                  );
                  return;
                }
                if (qty > qtyOwned) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('You only own $qtyOwned item(s)')),
                  );
                  return;
                }
                if (price == null || price <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter a valid price')),
                  );
                  return;
                }

                Navigator.pop(dialogContext);
                await _listItem(
                  itemId: _toInt(item['item']),
                  quantity: qty,
                  price: price,
                );
              },
              child: const Text('List'),
            ),
          ],
        );
      },
    );

    qtyController.dispose();
    priceController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDarkMode;

    Widget bodyContent = _loading
        ? const Center(child: CircularProgressIndicator())
        : _errorMessage != null
            ? Center(child: Text(_errorMessage!))
            : RefreshIndicator(
                onRefresh: _loadData,
                child: _items.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(24),
                        children: const [
                            SizedBox(height: 32),
                            Center(child: Text('No owned market items yet'))
                          ])
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final item = _items[i] as Map<String, dynamic>;
                          final qtyOwned = _toInt(item['quantity']);
                          final itemName =
                              item['item_name']?.toString() ?? 'Unnamed item';
                          final itemPrice = _toMoney(item['item_price']);

                          return AppleCard(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(itemName,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.w700)),
                                        const SizedBox(height: 4),
                                        Text('Base price: $itemPrice credits'),
                                        Text('Owned: $qtyOwned'),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton(
                                    onPressed: (qtyOwned <= 0 || _submitting)
                                        ? null
                                        : () => _openListDialog(item),
                                    child: _submitting
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2))
                                        : const Text('List'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              );

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Items'),
        actions: [
          if (_profile != null)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                    child: Text('Credits: ${_profile!['credits']}',
                        style: const TextStyle(fontWeight: FontWeight.w600)))),
          IconButton(
              icon: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
              onPressed: themeProvider.toggleTheme),
        ],
      ),
      body: AppleBackground(
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: bodyContent))),
    );
  }
}
