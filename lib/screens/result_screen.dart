import 'package:flutter/material.dart';
import '../models/product.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme.dart';
import 'dart:math' as math;

class ResultScreen extends StatefulWidget {
  final Product product;
  const ResultScreen({Key? key, required this.product}) : super(key: key);

  factory ResultScreen.mock() => ResultScreen(product: Product.demo());

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _slideController;
  late AnimationController _rotateController;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _rotateAnimation;

  @override
  void initState() {
    super.initState();

    // Scale animation for badge
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );

    // Slide animation for cards
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    // Rotate animation for image
    _rotateController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _rotateAnimation = CurvedAnimation(
      parent: _rotateController,
      curve: Curves.easeInOut,
    );

    // Start animations
    _scaleController.forward();
    _slideController.forward();
    _rotateController.forward();
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _slideController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  Widget _buildAnimatedBadge() {
    final isBoycott = widget.product.boycott;
    final gradient = isBoycott
        ? LinearGradient(
            colors: [AppColors.accentOrange, Colors.red.shade700],
          )
        : successGradient;
    final text = isBoycott ? 'BOYCOTT' : 'SAFE';
    final icon = isBoycott ? Icons.cancel : Icons.verified;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: isBoycott
                  ? AppColors.accentOrange.withOpacity(0.4)
                  : AppColors.accentGreen.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductImage() {
    return AnimatedBuilder(
      animation: _rotateAnimation,
      builder: (context, child) {
        return Transform.rotate(
          angle: (1 - _rotateAnimation.value) * math.pi * 2,
          child: child,
        );
      },
      child: Hero(
        tag: 'product_${widget.product.name}',
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: widget.product.imageUrl.isEmpty
                ? Icon(
                    Icons.local_drink,
                    size: 60,
                    color: AppColors.textSecondary,
                  )
                : CachedNetworkImage(
                    imageUrl: widget.product.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Center(
                      child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation(AppColors.primaryStart),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Icon(
                      Icons.broken_image,
                      size: 60,
                      color: AppColors.textSecondary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _slideController,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primaryStart.withOpacity(0.1),
                AppColors.primaryEnd.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              _buildProductImage(),
              const SizedBox(height: 20),
              Text(
                widget.product.name,
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                widget.product.brand,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 16),
              _buildAnimatedBadge(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _slideController,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _getIconForTitle(title),
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconForTitle(String title) {
    switch (title) {
      case 'Product Details':
        return Icons.info_outline;
      case 'Ingredients':
        return Icons.format_list_bulleted;
      case 'Additives':
        return Icons.science_outlined;
      default:
        return Icons.description;
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool isOutlined = false,
  }) {
    if (isOutlined) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            gradient: primaryGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryStart.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Product Result'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Share feature coming soon!')),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 100, left: 16, right: 16, bottom: 24),
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildInfoCard(
            'Product Details',
            [
              _buildInfoRow('Origin', widget.product.origin),
              _buildInfoRow('NutriScore', widget.product.nutriScore),
            ],
          ),
          if (widget.product.ingredients.isNotEmpty)
            _buildInfoCard(
              'Ingredients',
              [
                Text(
                  widget.product.ingredients,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          if (widget.product.additives.isNotEmpty)
            _buildInfoCard(
              'Additives',
              [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.product.additives
                      .map(
                        (additive) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accentOrange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.accentOrange.withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            additive,
                            style: TextStyle(
                              color: AppColors.accentOrange,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          const SizedBox(height: 24),
          _buildGradientButton(
            label: 'Save to History',
            icon: Icons.bookmark_add,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Saved to history!'),
                  backgroundColor: AppColors.accentGreen,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildGradientButton(
            label: 'Show Alternatives',
            icon: Icons.recommend,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Alternatives feature coming soon!'),
                ),
              );
            },
            isOutlined: true,
          ),
          const SizedBox(height: 12),
          _buildGradientButton(
            label: 'Scan Another Product',
            icon: Icons.qr_code_scanner,
            onTap: () {
              Navigator.pop(context);
            },
            isOutlined: true,
          ),
        ],
      ),
    );
  }
}
