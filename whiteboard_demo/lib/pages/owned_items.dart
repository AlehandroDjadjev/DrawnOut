import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class OwnedItemsPage extends StatefulWidget {
  const OwnedItemsPage({super.key});

  @override
  State<OwnedItemsPage> createState() => _OwnedItemsPageState();
}

class _OwnedItemsPageState extends State<OwnedItemsPage> {
  List<dynamic> _items = [];
  bool _loading = true;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _fetchOwned();
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

  Future<void> _fetchOwned() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;
      final base = dotenv.env['API_URL'] ?? '';
      final url = '$base/api/market/items/owned/';
      final resp = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        if (!mounted) return;
        setState(() => _items = list);
      }
    } catch (e) {}
    setState(() => _loading = false);
  }

  Future<void> _listItem(int itemId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;
    final base = dotenv.env['API_URL'] ?? '';
    final url = '$base/api/market/items/$itemId/list/';
    final resp = await http
        .post(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
    if (resp.statusCode == 201) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Item listed')));
      await _fetchOwned();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Failed to list')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Items'), actions: [
        if (_profile != null)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(child: Text('Credits: ${_profile!['credits']}')))
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchOwned,
              child: _items.isEmpty
                  ? ListView(children: const [
                      Center(
                          child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Text('No items')))
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final it = _items[i];
                        final qty = (it['quantity'] is int)
                            ? it['quantity'] as int
                            : int.tryParse(it['quantity']?.toString() ?? '0') ??
                                0;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            title: Text(it['item_name'] ?? 'Unnamed'),
                            subtitle:
                                Text('Price: ${it['item_price']} • Qty: $qty'),
                            trailing: ElevatedButton(
                              onPressed:
                                  qty <= 0 ? null : () => _listItem(it['item']),
                              child: const Text('List on Market'),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
