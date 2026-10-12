
import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';

class PaywallScreen extends StatefulWidget {
  final Movie movie;

  const PaywallScreen({
    super.key,
    required this.movie,
  });

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final TextEditingController _phoneController =
      TextEditingController();

  Timer? _poll;
  bool _waiting = false;
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _buyMovie() async {
    if (_waiting) return;

    final phone = _phoneController.text.trim();

    // Accept common Tanzanian phone-number formats.
    final digits = phone.replaceAll(RegExp(r'[\s()+-]'), '');

    if (!RegExp(r'^(0[67]\d{8}|255[67]\d{8})$')
        .hasMatch(digits)) {
      setState(() {
        _error =
            'Enter a valid Tanzanian mobile number, such as 0712345678 or 255712345678.';
      });
      return;
    }

    setState(() {
      _error = null;
      _waiting = true;
    });

    try {
      // Requests a mobile-money payment. No browser is opened.
      await Api.startMovieCheckout(
        widget.movie.id,
        phone: digits,
      );

      if (!mounted) return;

      setState(() {
        _error = null;
      });

      var tries = 0;
      _poll?.cancel();

      _poll = Timer.periodic(
        const Duration(seconds: 4),
        (timer) {
          tries++;
          if (tries >= 45) timer.cancel();
          _check();
        },
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _waiting = false;
        _error = 'Could not start payment. Please try again.\n$e';
      });
    }
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;

    _checking = true;

    try {
      final purchased =
          await Api.hasPurchasedMovie(widget.movie.id);

      if (!mounted) return;

      if (purchased) {
        _poll?.cancel();
        Navigator.pop(context, true);
      }
    } catch (_) {
      // Keep the screen open if checking temporarily fails.
    } finally {
      _checking = false;
    }
  }

  Future<void> _showPhonePopup() async {
    _phoneController.clear();
    setState(() => _error = null);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Mobile Money Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Movie: ${widget.movie.title}'),
              const SizedBox(height: 8),
              Text('Amount: ${widget.movie.price} TZS'),
              const SizedBox(height: 16),
              const Text('Enter the phone number for your mobile money account.'),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  hintText: '0712345678',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: _waiting
                  ? null
                  : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _waiting
                  ? null
                  : () async {
                      await _buyMovie();

                      if (mounted && _waiting) {
                        Navigator.pop(dialogContext);
                      }
                    },
              child: const Text('Send Payment Prompt'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final price = widget.movie.price;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buy Movie'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            if (widget.movie.posterUrl != null &&
                widget.movie.posterUrl!.isNotEmpty)
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    widget.movie.posterUrl!,
                    height: 220,
                    width: 150,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.movie, size: 100),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Text(
              widget.movie.title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'Buy once to unlock all paid episodes of this movie.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (price == null || price < 500)
              const Text(
                'The movie price is not set correctly. Please contact support.',
                textAlign: TextAlign.center,
              )
            else
              Text(
                'Price: $price TZS',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed:
                  _waiting || price == null || price < 500
                      ? null
                      : _showPhonePopup,
              child: const Text('Buy Movie'),
            ),
            if (_waiting) ...[
              const SizedBox(height: 20),
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              const Text(
                'Payment requested. Approve the prompt on your phone. Waiting for confirmation...',
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: _check,
                child: const Text('Check payment status'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}