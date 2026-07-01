import 'package:flutter/foundation.dart' show kIsWeb;
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
              data: data.isEmpty ? ' ' : data,
              size: 220,
              gapless: true,
              backgroundColor: Colors.white,
              // Explicit dark modules so the code renders on Flutter web too.
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
              // Surface failures instead of rendering a blank box.
              errorStateBuilder: (ctx, err) => SizedBox(
                width: 220,
                height: 220,
                child: Center(
                  child: Text(
                    "Couldn't draw the QR code.",
                    textAlign: TextAlign.center,
                    style: AppTheme.quick(size: 13, color: AppColors.inkSoft),
                  ),
                ),
              ),
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
  // An explicit controller starts the camera reliably (esp. on web) and lets us
  // dispose it cleanly when the screen closes.
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
        ref.invalidate(myCohortsProvider);
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
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            // Without this the camera failure path is just a black screen.
            errorBuilder: (ctx, error) => _ScannerError(error: error),
          ),
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

/// Shown in place of the black camera preview when the scanner can't start
/// (permission denied, no camera, or an unsupported browser).
class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final unsupported = error.errorCode == MobileScannerErrorCode.unsupported;
    final title = denied
        ? 'Camera access is blocked.'
        : unsupported
            ? "This device can't scan QR codes."
            : "The camera couldn't start.";
    final hint = StringBuffer();
    if (kIsWeb && denied) {
      hint.write('Allow camera access for this site in your browser, '
          'then reopen the scanner. ');
    }
    hint.write('You can also join a class by typing its code instead.');
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  color: Colors.white70, size: 48),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: AppTheme.baloo(
                      size: 16, weight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 8),
              Text(hint.toString(),
                  textAlign: TextAlign.center,
                  style: AppTheme.quick(size: 13, color: Colors.white70)),
            ],
          ),
        ),
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
