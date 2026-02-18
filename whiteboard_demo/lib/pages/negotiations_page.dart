import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import '../theme_provider.dart';

class NegotiationsPage extends StatefulWidget {
  final int? highlightProposalId;
  const NegotiationsPage({super.key, this.highlightProposalId});

  @override
  State<NegotiationsPage> createState() => _NegotiationsPageState();
}

class _NegotiationsPageState extends State<NegotiationsPage> {
  List<dynamic> _proposals = [];
  bool _loading = true;
  bool _submitting = false;
  Map<String, dynamic>? _profile;
  final ScrollController _scrollCtrl = ScrollController();
  int? _highlightId;

  String? get _currentUsername => _profile?['username']?.toString();

  String _readError(String body, String fallback) {
    if (body.isEmpty) return fallback;
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map && parsed['detail'] != null)
        return parsed['detail'].toString();
      if (parsed is Map && parsed['error'] != null)
        return parsed['error'].toString();
      return parsed.toString();
    } catch (_) {
      return fallback;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadProposals();
    _fetchProfile();
    _highlightId = widget.highlightProposalId;
  }

  String get _username => _profile?['username']?.toString() ?? '';

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
    setState(() => _submitting = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) {
      if (mounted) setState(() => _submitting = false);
      return;
    }
    final base = dotenv.env['API_URL'] ?? '';
    final url = '$base/api/market/counter-offers/respond/$counterId/$action/';
    final resp = await http
        .post(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
    if (resp.statusCode == 200) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Action successful')));
      await _loadProposals();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_readError(resp.body, 'Failed'))));
    }
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _respondToProposal(int proposalId, bool accept) async {
    setState(() => _submitting = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) {
      if (mounted) setState(() => _submitting = false);
      return;
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_readError(resp.body, 'Failed'))));
    }
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _withdrawProposal(int proposalId) async {
    setState(() => _submitting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;
      final base = dotenv.env['API_URL'] ?? '';
      final url = '$base/api/market/proposals/withdraw/$proposalId/';
      final resp = await http
          .post(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Proposal withdrawn')));
        await _loadProposals();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_readError(resp.body, 'Failed to withdraw'))));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Network error')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDarkMode;

    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : _proposals.isEmpty
            ? const Center(child: Text('No negotiations'))
            : ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(16),
                itemCount: _proposals.length,
                itemBuilder: (_, i) {
                  final p = _proposals[i];
                  final isSeller = _profile != null &&
                      (p['listing_seller_username'] == _username);
                  final isBuyer =
                      _profile != null && (p['buyer_username'] == _username);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    child: ExpansionTile(
                      key: ValueKey(p['id']),
                      initiallyExpanded:
                          _highlightId != null && _highlightId == p['id'],
                      title: Text(
                          'Listing ${p['listing_id']} - ${p['status']} • Qty: ${p['listing_quantity'] ?? 'N/A'}'),
                      subtitle: Text(
                          'Offer: ${p['proposed_price']} by ${p['buyer_username']}'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Row(children: [
                            if (isSeller) ...[
                              ElevatedButton(
                                  onPressed: p['status'] == 'pending' &&
                                          !_submitting
                                      ? () => _respondToProposal(p['id'], true)
                                      : null,
                                  child: const Text('Accept')),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                  onPressed: p['status'] == 'pending' &&
                                          !_submitting
                                      ? () => _respondToProposal(p['id'], false)
                                      : null,
                                  child: const Text('Decline')),
                            ],
                            if (isBuyer) ...[
                              ElevatedButton(
                                  onPressed:
                                      p['status'] == 'pending' && !_submitting
                                          ? () => _withdrawProposal(p['id'])
                                          : null,
                                  child: const Text('Withdraw')),
                              const SizedBox(width: 8),
                            ],
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(
                                    'Listing: ${p['listing_item_name'] ?? ''} by ${p['listing_seller_username'] ?? ''}')),
                          ]),
                        ),
                        if ((p['counters'] ?? []).isNotEmpty)
                          ...((p['counters'] as List<dynamic>).map((c) =>
                              ListTile(
                                title: Text(
                                    'Counter: ${c['price']} from ${c['from_username']}'),
                                subtitle: Text('Status: ${c['status']}'),
                                trailing: c['status'] == 'pending' &&
                                        (_currentUsername ==
                                                (c['to_username'] ?? '') ||
                                            isSeller)
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                            IconButton(
                                                icon: const Icon(Icons.check,
                                                    color: Colors.green),
                                                onPressed: () =>
                                                    _respondToCounter(
                                                        c['id'], 'accept')),
                                            IconButton(
                                                icon: const Icon(Icons.close,
                                                    color: Colors.red),
                                                onPressed: () =>
                                                    _respondToCounter(
                                                        c['id'], 'decline')),
                                          ])
                                    : null,
                              ))),
                      ],
                    ),
                  );
                },
              );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Negotiations'),
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
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: content)),
    );
  }
}
