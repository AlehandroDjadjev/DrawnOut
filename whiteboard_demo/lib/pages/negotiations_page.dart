import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class NegotiationsPage extends StatefulWidget {
  const NegotiationsPage({super.key});

  @override
  State<NegotiationsPage> createState() => _NegotiationsPageState();
}

class _NegotiationsPageState extends State<NegotiationsPage> {
  List<dynamic> _proposals = [];
  bool _loading = true;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _loadProposals();
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
    } catch (e) {}
  }

  Future<void> _loadProposals() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;
      final base = dotenv.env['API_URL'] ?? '';
      final url = '$base/api/market/proposals/my/';
      final resp = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        if (!mounted) return;
        setState(() => _proposals = list);
      }
    } catch (e) {}
    setState(() => _loading = false);
  }

  Future<void> _respondToCounter(int counterId, String action) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;
    final base = dotenv.env['API_URL'] ?? '';
    final url = '$base/api/market/counter-offers/respond/$counterId/$action/';
    final resp = await http
        .post(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
    if (resp.statusCode == 200) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Action successful')));
      await _loadProposals();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Failed')));
    }
  }

  Future<void> _respondToProposal(int proposalId, bool accept) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;
    final base = dotenv.env['API_URL'] ?? '';
    final url =
        '$base/api/market/trade-proposals/${accept ? 'accept' : 'decline'}/$proposalId/';
    final resp = await http
        .post(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
    if (resp.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(accept ? 'Proposal accepted' : 'Proposal declined')));
      await _loadProposals();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Negotiations'), actions: [
        if (_profile != null)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(child: Text('Credits: ${_profile!['credits']}')))
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _proposals.isEmpty
              ? const Center(child: Text('No negotiations'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _proposals.length,
                  itemBuilder: (_, i) {
                    final p = _proposals[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        title: Text(
                            'Listing ${p['listing_id']} - ${p['status']} • Qty listed: ${p['listing_quantity'] ?? 'N/A'}'),
                        subtitle: Text(
                            'Offer: ${p['proposed_price']} by ${p['buyer_username']}'),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                ElevatedButton(
                                    onPressed: p['status'] == 'pending'
                                        ? () =>
                                            _respondToProposal(p['id'], true)
                                        : null,
                                    child: const Text('Accept')),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                    onPressed: p['status'] == 'pending'
                                        ? () =>
                                            _respondToProposal(p['id'], false)
                                        : null,
                                    child: const Text('Decline')),
                                const SizedBox(width: 8),
                                Text(
                                    'Listing: ${p['listing_item_name'] ?? ''} by ${p['listing_seller_username'] ?? ''}'),
                              ],
                            ),
                          ),
                          if ((p['counters'] ?? []).isNotEmpty)
                            ...((p['counters'] as List<dynamic>)
                                .map((c) => ListTile(
                                      title: Text(
                                          'Counter: ${c['price']} from ${c['from_username']}'),
                                      subtitle: Text('Status: ${c['status']}'),
                                      trailing: c['status'] == 'pending'
                                          ? Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.check,
                                                      color: Colors.green),
                                                  onPressed: () =>
                                                      _respondToCounter(
                                                          c['id'], 'accept'),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.close,
                                                      color: Colors.red),
                                                  onPressed: () =>
                                                      _respondToCounter(
                                                          c['id'], 'decline'),
                                                ),
                                              ],
                                            )
                                          : null,
                                    ))),
                          ButtonBar(
                            children: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close')),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
