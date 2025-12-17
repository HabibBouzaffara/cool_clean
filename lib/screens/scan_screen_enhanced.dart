// lib/screens/scan_screen_enhanced.dart
// Enhanced scan screen combining beautiful UI with comprehensive debugging

import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../routes.dart';
import '../services/openfoodfacts_service.dart';
import '../models/product.dart';
import '../theme.dart';

class ScanScreenEnhanced extends StatefulWidget {
  const ScanScreenEnhanced({Key? key}) : super(key: key);

  @override
  State<ScanScreenEnhanced> createState() => _ScanScreenEnhancedState();
}

class _ScanScreenEnhancedState extends State<ScanScreenEnhanced>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? controller;
  List<CameraDescription> cameras = [];
  final barcodeScanner = BarcodeScanner();
  final ofService = OpenFoodFactsService();
  final ImageLabeler imageLabeler = ImageLabeler(
    options: ImageLabelerOptions(confidenceThreshold: 0.6),
  );
  final TextRecognizer textRecognizer = TextRecognizer();
  bool _processing = false;
  Timer? _resumeTimer;
  
  // Fallback: if no barcode found after this many seconds, try capturing a photo
  static const int kFallbackSeconds = 6;
  Timer? _fallbackTimer;

  // Animation controllers for UI
  late AnimationController _scanLineController;
  late AnimationController _pulseController;
  late Animation<double> _scanLineAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Scan line animation
    _scanLineController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    _scanLineAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanLineController, curve: Curves.easeInOut),
    );

    // Pulse animation for corners
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initCameraPermission();
  }

  Future<void> _initCameraPermission() async {
    debugPrint('[SCAN] Requesting camera permission...');
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      debugPrint('[SCAN] Camera permission denied');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Camera permission is required.")),
        );
      }
      return;
    }
    debugPrint('[SCAN] Camera permission granted');
    await _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      debugPrint('[SCAN] Initializing camera...');
      cameras = await availableCameras();
      if (cameras.isEmpty) throw "No cameras available";
      
      debugPrint('[SCAN] Found ${cameras.length} camera(s)');
      controller = CameraController(
        cameras.first,
        ResolutionPreset.high, // use high for better detection
        enableAudio: false,
      );
      
      await controller!.initialize();
      debugPrint('[SCAN] Camera initialized successfully');
      
      // Start the frame stream
      await controller!.startImageStream(_processCameraImage);
      debugPrint('[SCAN] Image stream started');
      
      // Start fallback timer
      _startFallbackTimer();
      setState(() {});
    } catch (e) {
      debugPrint('[SCAN] Camera initialization error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Camera error: $e")),
        );
      }
    }
  }

  void _startFallbackTimer() {
    _fallbackTimer?.cancel();
    debugPrint('[SCAN] Starting fallback timer ($kFallbackSeconds seconds)');
    _fallbackTimer = Timer(Duration(seconds: kFallbackSeconds), () async {
      debugPrint('[SCAN] Fallback timer triggered');
      await _tryImageFileScanFallback();
    });
  }

  void _resetFallbackTimer() {
    _fallbackTimer?.cancel();
    _startFallbackTimer();
  }

  Future<void> _tryImageFileScanFallback() async {
    if (controller == null || !controller!.value.isInitialized) {
      debugPrint('[SCAN] Controller not ready for fallback');
      _startFallbackTimer();
      return;
    }

    // Stop stream
    try {
      debugPrint('[SCAN] Stopping image stream for fallback');
      await controller!.stopImageStream();
    } catch (e) {
      debugPrint('[SCAN] Error stopping stream: $e');
    }

    XFile? xfile;
    try {
      debugPrint('[SCAN] Attempting fallback scan...');
      xfile = await controller!.takePicture();
      debugPrint('[SCAN] Picture taken: ${xfile.path}');
      
      final inputImage = InputImage.fromFilePath(xfile.path);

      // 1. Try Barcode
      debugPrint('[SCAN] Attempting barcode detection...');
      final barcodes = await barcodeScanner.processImage(inputImage);
      if (barcodes.isNotEmpty) {
        final code = barcodes.first.rawValue;
        if (code != null && code.isNotEmpty) {
          debugPrint('[SCAN] ✅ Barcode detected: $code');
          await _onBarcodeDetected(code);
          return;
        }
      }
      debugPrint('[SCAN] No barcode detected, proceeding with text and image analysis.');

      // 2. Always run image labeling and log the results
      debugPrint('[SCAN] Attempting image labeling...');
      final labels = await imageLabeler.processImage(inputImage);
      String? topLabel;
      if (labels.isNotEmpty) {
        for (final label in labels) {
          debugPrint('[SCAN] Label detected: ${label.label} | confidence: ${label.confidence.toStringAsFixed(2)}');
        }
        topLabel = labels.first.label;
        debugPrint('[SCAN] Top label: $topLabel');
      } else {
        debugPrint('[SCAN] No labels detected in the image.');
      }

      // 3. Try Text Recognition
      debugPrint('[SCAN] Trying text recognition...');
      final recognizedText = await textRecognizer.processImage(inputImage);
      String? bestText;
      
      // New heuristic: find the text block that's highest up in the image
      if (recognizedText.blocks.isNotEmpty) {
        String? candidate;
        double minY = double.infinity;
        for (final block in recognizedText.blocks) {
          final text = block.text.trim().replaceAll('\n', ' ');
          debugPrint('[SCAN] Text block found: "$text" at Y: ${block.boundingBox.top}');
          if (text.length > 2 && block.boundingBox.top < minY) {
            minY = block.boundingBox.top;
            candidate = text;
          }
        }
        if (candidate != null) {
          bestText = candidate;
          debugPrint('[SCAN] ✅ Text detected (top-most): $bestText');
        }
      } else {
        debugPrint('[SCAN] No text blocks detected.');
      }

      // Prioritize text recognition results for product search
      if (bestText != null) {
        debugPrint('[SCAN] Searching for product with text: "$bestText"');
        final product = await ofService.searchByName(bestText);
        if (product != null) {
          debugPrint('[SCAN] ✅ Product found for text: "${product.name}"');
          Navigator.pushReplacementNamed(
            context,
            Routes.result,
            arguments: product,
          );
          return;
        } else {
          debugPrint('[SCAN] ❌ No product found for text "$bestText".');
        }
      } else {
        debugPrint('[SCAN] No usable text detected.');
      }

      // 4. If text recognition fails, fall back to using the top image label
      if (topLabel != null) {
        debugPrint('[SCAN] Falling back to top image label. Searching for product with label: "$topLabel"');
        final product = await ofService.searchByName(topLabel);
        if (product != null) {
          debugPrint('[SCAN] ✅ Product found for label: "${product.name}"');
          Navigator.pushReplacementNamed(
            context,
            Routes.result,
            arguments: product,
          );
          return;
        } else {
          debugPrint('[SCAN] ❌ No product found for label "$topLabel"');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('No product found for "$topLabel"${bestText != null ? ' or text "$bestText"' : ''}'),
              ),
            );
          }
        }
      } else {
        // Only show this if both text and label searches have nothing to go on
        debugPrint('[SCAN] ❌ No product, text, or labels could be identified.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No product, text, or labels could be identified.'),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[SCAN] ❌ Fallback capture error: $e');
    } finally {
      // Restart stream
      try {
        if (controller != null && controller!.value.isInitialized) {
          debugPrint('[SCAN] Restarting image stream...');
          await controller!.startImageStream(_processCameraImage);
        }
      } catch (e) {
        debugPrint('[SCAN] Error restarting stream after fallback: $e');
      }
      _startFallbackTimer();
    }
  }

  void _processCameraImage(CameraImage image) async {
    if (_processing) return;
    _processing = true;

    try {
      // Combine plane bytes to a single Uint8List (as ML Kit expects)
      final WriteBuffer buffer = WriteBuffer();
      for (final plane in image.planes) {
        buffer.putUint8List(plane.bytes);
      }
      final bytes = buffer.done().buffer.asUint8List();

      // Build metadata using ML Kit API
      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotationValue.fromRawValue(
              cameras.first.sensorOrientation,
            ) ??
            InputImageRotation.rotation0deg,
        format: InputImageFormatValue.fromRawValue(image.format.raw) ??
            InputImageFormat.nv21,
        bytesPerRow: image.planes.first.bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: metadata);
      final barcodes = await barcodeScanner.processImage(inputImage);

      if (barcodes.isNotEmpty) {
        final code = barcodes.first.rawValue;
        if (code != null && code.isNotEmpty) {
          debugPrint('[SCAN] ✅ Barcode detected in stream: $code');
          await _onBarcodeDetected(code);
          return;
        }
      }

      // No barcode: reset fallback timer to keep trying until fallback fires
      _resetFallbackTimer();
    } catch (e) {
      debugPrint('[SCAN] Error processing camera image: $e');
      // Continue — fallback will be attempted eventually
    } finally {
      // Throttle a bit so we don't hog CPU
      Future.delayed(const Duration(milliseconds: 150), () {
        _processing = false;
      });
    }
  }

  Future<void> _onBarcodeDetected(String code) async {
    debugPrint('[SCAN] Processing barcode: $code');
    try {
      await controller?.stopImageStream();
    } catch (e) {
      debugPrint('[SCAN] Error stopping stream: $e');
    }

    if (!mounted) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primaryStart.withOpacity(0.9),
                AppColors.primaryEnd.withOpacity(0.9),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: 16),
              const Text(
                'Scanning product...',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      debugPrint('[SCAN] Fetching product data from OpenFoodFacts...');
      final product = await ofService.fetchByBarcode(code);
      Navigator.of(context).pop(); // close loading

      if (product != null) {
        debugPrint('[SCAN] ✅ Product found: ${product.name}');
        Navigator.pushReplacementNamed(
          context,
          Routes.result,
          arguments: product,
        );
        return;
      } else {
        debugPrint('[SCAN] ❌ Product not found for barcode: $code');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Product not found: $code')),
        );
      }
    } catch (e) {
      debugPrint('[SCAN] ❌ Lookup error: $e');
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lookup error: $e')),
      );
    } finally {
      _resumeScanningWithDelay();
    }
  }

  void _resumeScanningWithDelay() {
    debugPrint('[SCAN] Resuming scanning after delay...');
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 2), () async {
      try {
        if (controller != null && controller!.value.isInitialized) {
          await controller!.startImageStream(_processCameraImage);
          debugPrint('[SCAN] Scanning resumed');
        }
      } catch (e) {
        debugPrint('[SCAN] Error resuming scan: $e');
      } finally {
        _processing = false;
        _startFallbackTimer();
      }
    });
  }

  // UI BUILDING METHODS

  Widget _buildScanOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth * 0.7;
        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              children: [
                // Animated corners
                ..._buildAnimatedCorners(size),
                // Scanning line
                AnimatedBuilder(
                  animation: _scanLineAnimation,
                  builder: (context, child) {
                    return Positioned(
                      top: size * _scanLineAnimation.value,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              AppColors.secondaryStart,
                              Colors.transparent,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.secondaryStart,
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildAnimatedCorners(double size) {
    return [
      // Top-left
      _buildCorner(0, 0, [true, false, false, true]),
      // Top-right
      _buildCorner(0, size - 30, [true, true, false, false]),
      // Bottom-left
      _buildCorner(size - 30, 0, [false, false, true, true]),
      // Bottom-right
      _buildCorner(size - 30, size - 30, [false, true, true, false]),
    ];
  }

  Widget _buildCorner(double top, double left, List<bool> borders) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Positioned(
          top: top,
          left: left,
          child: Opacity(
            opacity: _pulseAnimation.value,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                border: Border(
                  top: borders[0]
                      ? const BorderSide(color: Colors.white, width: 4)
                      : BorderSide.none,
                  right: borders[1]
                      ? const BorderSide(color: Colors.white, width: 4)
                      : BorderSide.none,
                  bottom: borders[2]
                      ? const BorderSide(color: Colors.white, width: 4)
                      : BorderSide.none,
                  left: borders[3]
                      ? const BorderSide(color: Colors.white, width: 4)
                      : BorderSide.none,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.7),
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlButton(
            icon: controller?.value.flashMode == FlashMode.torch
                ? Icons.flash_on
                : Icons.flash_off,
            label: 'Flash',
            onTap: () async {
              if (controller == null) return;
              try {
                final mode = controller!.value.flashMode;
                final newMode =
                    mode == FlashMode.off ? FlashMode.torch : FlashMode.off;
                await controller!.setFlashMode(newMode);
                debugPrint('[SCAN] Flash mode changed to: $newMode');
                setState(() {});
              } catch (e) {
                debugPrint('[SCAN] Error toggling flash: $e');
              }
            },
          ),
          _buildControlButton(
            icon: Icons.camera_alt,
            label: 'Capture',
            onTap: () {
              debugPrint('[SCAN] Manual capture triggered');
              _tryImageFileScanFallback();
            },
            isPrimary: true,
          ),
          _buildControlButton(
            icon: Icons.help_outline,
            label: 'Help',
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Scanning Tips'),
                  content: const Text(
                    '• Point camera at barcode\n'
                    '• Keep product well-lit\n'
                    '• Hold steady for best results\n'
                    '• Auto-capture activates after ${kFallbackSeconds}s\n'
                    '• Use manual capture button if needed',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Got it'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: isPrimary ? primaryGradient : null,
            color: isPrimary ? null : Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (controller == null || !controller!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                'Initializing camera...',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(controller!),
        // Gradient overlay for better contrast
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.3),
                Colors.transparent,
                Colors.transparent,
                Colors.black.withOpacity(0.5),
              ],
            ),
          ),
        ),
        _buildScanOverlay(),
      ],
    );
  }

  @override
  void dispose() {
    debugPrint('[SCAN] Disposing scan screen...');
    WidgetsBinding.instance.removeObserver(this);
    controller?.dispose();
    barcodeScanner.close();
    imageLabeler.close();
    textRecognizer.close();
    _resumeTimer?.cancel();
    _fallbackTimer?.cancel();
    _scanLineController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (controller == null) return;
    if (state == AppLifecycleState.inactive) {
      debugPrint('[SCAN] App inactive, disposing camera');
      controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      debugPrint('[SCAN] App resumed, reinitializing camera');
      _initCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "Scan Product",
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(child: _buildCameraPreview()),
          _buildControls(),
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.black,
            child: const Text(
              "Align the barcode within the frame.\n"
              "Auto-capture will trigger if no barcode is detected.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
