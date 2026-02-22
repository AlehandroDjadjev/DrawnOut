import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme_provider.dart';
import '../ui/apple_ui.dart';

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
  String get _username => _profile?['username']?.toString() ?? '';

  String _readError(String body, String fallback) {
    if (body.isEmpty) return fallback;
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map && parsed['detail'] != null) {
        return parsed['detail'].toString();
      }
      if (parsed is Map && parsed['error'] != null) {
        return parsed['error'].toString();
      }
      return parsed.toString();
    } catch (_) {
      return fallback;
    }
  }

  @override
  void initState() {
    super.initState();
    _highlightId = widget.highlightProposalId;
    _loadProposals();
    _fetchProfile();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;

      final base = dotenv.env['API_URL'] ?? '';
      final url = '$base/api/auth/profile/';
      final resp = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (resp.statusCode == 200) {
        final map = jsonDecode(resp.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() => _profile = map);
      }
    } catch (_) {}
  }

  Future<void> _loadProposals() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;

      final base = dotenv.env['API_URL'] ?? '';
      final url = '$base/api/market/proposals/my/';
      final resp = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        if (!mounted) return;
        setState(() => _proposals = list);
      }
    } catch (_) {
      // Preserve behavior: silent load failure with existing state retained.
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _respondToCounter(int counterId, String action) async {
    if (!mounted) return;
    setState(() => _submitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;

      final base = dotenv.env['API_URL'] ?? '';
      final url = '$base/api/market/counter-offers/respond/$counterId/$action/';
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (!mounted) return;

      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Action successful')),
        );
        await _loadProposals();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_readError(resp.body, 'Failed'))),
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

  Future<void> _respondToProposal(int proposalId, bool accept) async {
    if (!mounted) return;
    setState(() => _submitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;

      final base = dotenv.env['API_URL'] ?? '';
      final url =
          '$base/api/market/trade-proposals/${accept ? 'accept' : 'decline'}/$proposalId/';
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (!mounted) return;

      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(accept ? 'Proposal accepted' : 'Proposal declined'),
          ),
        );
        await _loadProposals();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_readError(resp.body, 'Failed'))),
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

  Future<void> _withdrawProposal(int proposalId) async {
    if (!mounted) return;
    setState(() => _submitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;

      final base = dotenv.env['API_URL'] ?? '';
      final url = '$base/api/market/proposals/withdraw/$proposalId/';
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (!mounted) return;

      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Proposal withdrawn')),
        );
        await _loadProposals();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_readError(resp.body, 'Failed to withdraw'))),
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

  Widget _statusPill(ThemeData theme, String status) {
    final normalized = status.toLowerCase();
    Color bg;
    Color fg;

    if (normalized == 'pending') {
      bg = Colors.orange.withOpacity(0.18);
      fg = Colors.orange.shade800;
    } else if (normalized == 'accepted') {
      bg = Colors.green.withOpacity(0.18);
      fg = Colors.green.shade800;
    } else if (normalized == 'declined') {
      bg = Colors.red.withOpacity(0.16);
      fg = Colors.red.shade800;
    } else {
      bg = theme.colorScheme.primary.withOpacity(0.14);
      fg = theme.colorScheme.primary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildActions(
    dynamic proposal,
    bool isSeller,
    bool isBuyer,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (isSeller)
          ElevatedButton(
            onPressed: proposal['status'] == 'pending' && !_submitting
                ? () => _respondToProposal(proposal['id'], true)
                : null,
            child: const Text('Accept'),
          ),
        if (isSeller)
          OutlinedButton(
            onPressed: proposal['status'] == 'pending' && !_submitting
                ? () => _respondToProposal(proposal['id'], false)
                : null,
            child: const Text('Decline'),
          ),
        if (isBuyer)
          ElevatedButton(
            onPressed: proposal['status'] == 'pending' && !_submitting
                ? () => _withdrawProposal(proposal['id'])
                : null,
            child: const Text('Withdraw'),
          ),
      ],
    );
  }

  Widget _buildProposalCard(ThemeData theme, dynamic proposal) {
    final isSeller =
        _profile != null && (proposal['listing_seller_username'] == _username);
    final isBuyer = _profile != null && (proposal['buyer_username'] == _username);
    final counters = (proposal['counters'] as List<dynamic>? ?? []);

    return AppleCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.zero,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey(proposal['id']),
          initiallyExpanded: _highlightId != null && _highlightId == proposal['id'],
          tilePadding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  'Listing ${proposal['listing_id']} | Qty: ${proposal['listing_quantity'] ?? 'N/A'}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _statusPill(theme, (proposal['status'] ?? '').toString()),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Offer: ${proposal['proposed_price']} by ${proposal['buyer_username']}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.72),
              ),
            ),
          ),
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildActions(proposal, isSeller, isBuyer),
                  const SizedBox(height: 10),
                  Text(
                    'Listing: ${proposal['listing_item_name'] ?? ''} by ${proposal['listing_seller_username'] ?? ''}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (counters.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ...counters.map((counter) {
                      final canRespond = counter['status'] == 'pending' &&
                          (_currentUsername ==
                                  (counter['to_username'] ?? '').toString() ||
                              isSeller);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withOpacity(0.55),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Counter: ${counter['price']} from ${counter['from_username']}',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Status: ${counter['status']}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              if (canRespond)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.check, color: Colors.green),
                                      onPressed: () =>
                                          _respondToCounter(counter['id'], 'accept'),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, color: Colors.red),
                                      onPressed: () =>
                                          _respondToCounter(counter['id'], 'decline'),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyState(ThemeData theme) {
    if (_loading) {
      return const Center(
        key: ValueKey('negotiations-loading'),
        child: CircularProgressIndicator(),
      );
    }

    if (_proposals.isEmpty) {
      return Center(
        key: const ValueKey('negotiations-empty'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: AppleCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.handshake_outlined,
                    size: 52,
                    color: theme.colorScheme.primary.withOpacity(0.55),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No negotiations',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      key: const ValueKey('negotiations-list'),
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(16),
      itemCount: _proposals.length,
      itemBuilder: (_, i) => _buildProposalCard(theme, _proposals[i]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDarkMode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Negotiations'),
        actions: [
          if (_profile != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  'Credits: ${_profile!['credits']}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          IconButton(
            icon: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
            onPressed: themeProvider.toggleTheme,
          ),
        ],
      ),
      body: AppleBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _buildBodyState(theme),
            ),
          ),
        ),
      ),
    );
  }
}
