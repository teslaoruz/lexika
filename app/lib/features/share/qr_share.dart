import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/api_client.dart';
import '../../api/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';

/// QR payloads use a tiny custom scheme the in-app scanner understands:
/// `lexika://deck/{id}` imports that deck; `lexika://class/{CODE}` joins a class.
String deckQrData(int deckId) => 'lexika://deck/$deckId';
String classQrData(String joinCode) => 'lexika://class/$joinCode';

/// Show a QR code in a dialog (teacher shows it; students scan it).
void showQrDialog(BuildContext context,
    {required String data, required String title, String? subtitle}) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(title,
          textAlign: TextAlign.center,
          style: AppTheme.baloo(size: 18, weight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: data,
              size: 220,
              backgroundColor: Colors.white,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 12),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: AppTheme.quick(
                    size: 13, height: 1.4, color: AppColors.inkSoft)),
          ],
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        AppButton(
          label: 'Done',
          bg: AppColors.violet,
          onTap: () => Navigator.of(ctx).pop(),
        ),
      ],
    ),
  );
}

/// Fullscreen camera scanner. Reads a `lexika://` QR and either imports a deck
/// or joins a class, then pops with a result message.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  bool _handled = false;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes.isNotEmpty
        ? capture.barcodes.first.rawValue
        : null;
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'lexika') return; // ignore other QRs
    _handled = true;
    final api = ref.read(apiClientProvider);
    String message;
    try {
      if (uri.host == 'deck' && uri.pathSegments.isNotEmpty) {
        final deck = await api.importDeck(int.parse(uri.pathSegments.first));
        ref.invalidate(decksProvider);
        message = 'Added deck “${deck.name}”.';
      } else if (uri.host == 'class' && uri.pathSegments.isNotEmpty) {
        final c = await api.joinCohort(uri.pathSegments.first);
        ref.invalidate(cohortProvider);
        ref.invalidate(leaderboardProvider);
        message = 'Joined “${c.name}”.';
      } else {
        _handled = false;
        return;
      }
    } on ApiException catch (e) {
      message = e.message;
    } catch (_) {
      message = "That QR code didn't work.";
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan a Lexika QR'),
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(onDetect: _onDetect),
          // Simple viewfinder.
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white70, width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Text(
              'Point at a deck-share or class-join QR code',
              textAlign: TextAlign.center,
              style: AppTheme.quick(size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Push the scanner.
void openScanner(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const ScanScreen()),
  );
}
