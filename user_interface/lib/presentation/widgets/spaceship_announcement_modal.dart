import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lecture_companion_ui/domain/entities/app_transmission.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/l10n/generated/app_localizations.dart';

/// 宇宙船の窓（ポータル）モチーフのお知らせアイテムモデル
class SpaceshipAnnouncementItem {
  final String id;
  final String? category;
  final String title;
  final String content;
  final String? imageUrl;
  final IconData? icon;
  final List<Color>? gradient;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SpaceshipAnnouncementItem({
    required this.id,
    this.category,
    required this.title,
    required this.content,
    this.imageUrl,
    this.icon,
    this.gradient,
    this.actionLabel,
    this.onAction,
  });

  factory SpaceshipAnnouncementItem.fromTransmission(
    AppTransmission t, {
    VoidCallback? onAction,
  }) {
    return SpaceshipAnnouncementItem(
      id: t.id,
      category: t.category,
      title: t.title,
      content: t.content,
      imageUrl: t.resolvedImageUrl,
      actionLabel: t.actionLabel,
      onAction: onAction,
    );
  }
}

/// デフォルトのダミーお知らせデータ（動作確認用）
final List<SpaceshipAnnouncementItem> kDefaultAnnouncements = [
  SpaceshipAnnouncementItem(
    id: '1',
    category: '✨ NEW FEATURE',
    title: 'Galaxy Map 2.0 Released!',
    content: 'Experience knowledge connections with interactive star node exploration in our upgraded Galaxy Map.',
    icon: Icons.auto_awesome_rounded,
    gradient: [const Color(0xFF1E1035), const Color(0xFF3B1D60), const Color(0xFF6B2FB3)],
    actionLabel: 'Open Map',
  ),
  SpaceshipAnnouncementItem(
    id: '2',
    category: '🚀 UPDATE',
    title: 'Real-time AI Transcription Upgrade',
    content: 'Enhanced noise cancellation enables sharper voice capture during lectures with faster summary generation.',
    icon: Icons.graphic_eq_rounded,
    gradient: [const Color(0xFF0D253F), const Color(0xFF144570), const Color(0xFF1D78B4)],
    actionLabel: 'View Settings',
  ),
  SpaceshipAnnouncementItem(
    id: '3',
    category: '🛰️ NOTICE',
    title: 'Orbit Annual Conference',
    content: 'Join our online interactive session showcasing future learning experiences and exclusive feature previews.',
    icon: Icons.rocket_launch_rounded,
    gradient: [const Color(0xFF331C08), const Color(0xFF663700), AppColors.starGold.withValues(alpha: 0.8)],
    actionLabel: 'Learn More',
  ),
];

/// 宇宙船の窓（ポータル）風お知らせモーダルを表示する関数
Future<void> showSpaceshipAnnouncementModal(
  BuildContext context, {
  List<SpaceshipAnnouncementItem>? announcements,
}) async {
  final items = announcements ?? kDefaultAnnouncements;
  if (items.isEmpty) return;

  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'SpaceshipAnnouncementModal',
    barrierColor: Colors.black.withValues(alpha: 0.75),
    transitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (context, anim1, anim2) {
      return SpaceshipAnnouncementDialog(items: items);
    },
    transitionBuilder: (context, anim1, anim2, child) {
      final curved = CurvedAnimation(parent: anim1, curve: Curves.easeOutBack);
      return Transform.scale(
        scale: curved.value,
        child: FadeTransition(
          opacity: anim1,
          child: child,
        ),
      );
    },
  );
}

/// 宇宙船のポータルモーダルダイアログ
class SpaceshipAnnouncementDialog extends StatefulWidget {
  final List<SpaceshipAnnouncementItem> items;

  const SpaceshipAnnouncementDialog({
    super.key,
    required this.items,
  });

  @override
  State<SpaceshipAnnouncementDialog> createState() => _SpaceshipAnnouncementDialogState();
}

class _SpaceshipAnnouncementDialogState extends State<SpaceshipAnnouncementDialog> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = (screenSize.width * 0.88).clamp(300.0, 440.0);
    final dialogHeight = (screenSize.height * 0.75).clamp(520.0, 640.0);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: dialogWidth,
          height: dialogHeight,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. 宇宙船のぼかしグラス背景＋八角形切り欠きフレーム
              Positioned.fill(
                child: ClipPath(
                  clipper: _SpaceshipPortalClipper(),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B101D).withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
              ),

              // 2. ペイントによる幾何学フレーム＆輝くネオン枠線
              Positioned.fill(
                child: CustomPaint(
                  painter: _SpaceshipPortalPainter(
                    glowColor: AppColors.starGold,
                    borderAccent: AppColors.cosmicBlue,
                  ),
                ),
              ),

              // 3. モーダルのメインコンテンツ
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: Column(
                    children: [
                      // --- ヘッダーHUD ---
                      _buildHeaderHUD(context),
                      const SizedBox(height: 12),

                      // --- スワイプ可能なコンテンツエリア（カルーセル） ---
                      Expanded(
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: widget.items.length,
                          onPageChanged: (index) {
                            setState(() {
                              _currentPage = index;
                            });
                          },
                          itemBuilder: (context, index) {
                            return _buildAnnouncementPage(widget.items[index]);
                          },
                        ),
                      ),

                      const SizedBox(height: 8),

                      // --- 軌道ドットインジケーター（ページ送り） ---
                      _buildOrbitIndicator(),

                      const SizedBox(height: 14),

                      // --- フッターアクション ---
                      _buildFooter(context),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ヘッダーHUD（ステータスランプ ＋ TRANSMISSION表示 ＋ 閉じるボタン）
  Widget _buildHeaderHUD(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          // 点滅する緑のステータスLED
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.growthGreen,
              boxShadow: [
                BoxShadow(
                  color: AppColors.growthGreen.withValues(alpha: 0.8),
                  blurRadius: 6,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          
          // SFテイストのHUDキャプション
          Text(
            'TRANSMISSION // ${_currentPage + 1}/${widget.items.length}',
            style: TextStyle(
              color: AppColors.universe.textComet,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              fontFamily: 'monospace',
            ),
          ),

          const Spacer(),

          // 宇宙船メカ風 閉じるボタン
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.close_rounded,
                color: AppColors.universe.textStarlight,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 各お知らせページ（画像ビューポート ＋ カテゴリ ＋ タイトル ＋ 本文）
  Widget _buildAnnouncementPage(SpaceshipAnnouncementItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- 宇宙船の窓（メイン画像ビューポート） ---
        AspectRatio(
          aspectRatio: 1.85,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.universe.glassBorder,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 背景グラデーション / 画像
                if (item.imageUrl != null)
                  Image.network(
                    item.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _buildFallbackGraphic(item),
                  )
                else
                  _buildFallbackGraphic(item),

                // 画像上のスキャンライン / コーナーアクセント overlay
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.4),
                        ],
                      ),
                    ),
                  ),
                ),

                // 四隅のサイバーフレームブラケット
                const Positioned(
                  top: 8, left: 8,
                  child: Icon(Icons.crop_free_rounded, color: Colors.white38, size: 14),
                ),
                const Positioned(
                  bottom: 8, right: 8,
                  child: Icon(Icons.crop_free_rounded, color: Colors.white38, size: 14),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // --- カテゴリバッジ (NULLでない場合のみ表示) ---
        if (item.category != null && item.category!.trim().isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.starGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.starGold.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Text(
              item.category!,
              style: const TextStyle(
                color: AppColors.starGold,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // --- タイトル ---
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
            height: 1.25,
            letterSpacing: 0.3,
          ),
        ),

        const SizedBox(height: 8),

        // --- 本文（スクロール対応） ---
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Text(
              item.content,
              style: TextStyle(
                color: AppColors.universe.textStarlight.withValues(alpha: 0.88),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 画像がない場合のSFグラフィック（星雲＆キラキラ感）
  Widget _buildFallbackGraphic(SpaceshipAnnouncementItem item) {
    final colors = item.gradient ?? [
      const Color(0xFF0F172A),
      const Color(0xFF1E293B),
      AppColors.cosmicBlue.withValues(alpha: 0.5),
    ];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 背景の薄い放射状発光
          Positioned(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.starGold.withValues(alpha: 0.15),
              ),
            ),
          ),
          // 幾何学モチーフアイコン
          Icon(
            item.icon ?? Icons.auto_awesome,
            size: 48,
            color: AppColors.starGold.withValues(alpha: 0.9),
          ),
        ],
      ),
    );
  }

  /// 軌道ドットインジケーター（Planet Orbit Dots）
  Widget _buildOrbitIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.items.length, (index) {
        final isSelected = index == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isSelected ? 20.0 : 6.0,
          height: 6.0,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: isSelected
                ? AppColors.starGold
                : AppColors.universe.textComet.withValues(alpha: 0.4),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.starGold.withValues(alpha: 0.8),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
        );
      }),
    );
  }

  /// フッター（アクションボタン）
  Widget _buildFooter(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentItem = widget.items[_currentPage];

    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton(
        onPressed: () {
          Navigator.of(context).pop();
          currentItem.onAction?.call();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.starGold,
          foregroundColor: Colors.black,
          elevation: 4,
          shadowColor: AppColors.starGold.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              currentItem.actionLabel ?? l10n.spaceshipAnnouncementGotIt,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_rounded, size: 16),
          ],
        ),
      ),
    );
  }
}

/// 宇宙船ポータルの切欠き角（八角形）クリッパー
class _SpaceshipPortalClipper extends CustomClipper<Path> {
  final double cornerCut = 20.0;

  @override
  Path getClip(Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;
    final c = cornerCut;

    path.moveTo(c, 0);
    path.lineTo(w - c, 0);
    path.lineTo(w, c);
    path.lineTo(w, h - c);
    path.lineTo(w - c, h);
    path.lineTo(c, h);
    path.lineTo(0, h - c);
    path.lineTo(0, c);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// 宇宙船ポータルの枠線・グラデーションネオン・メカニカルアクセントを描画するペインター
class _SpaceshipPortalPainter extends CustomPainter {
  final Color glowColor;
  final Color borderAccent;
  final double cornerCut = 20.0;

  _SpaceshipPortalPainter({
    required this.glowColor,
    required this.borderAccent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final c = cornerCut;

    // パスの生成（八角形切欠き）
    final path = Path()
      ..moveTo(c, 0)
      ..lineTo(w - c, 0)
      ..lineTo(w, c)
      ..lineTo(w, h - c)
      ..lineTo(w - c, h)
      ..lineTo(c, h)
      ..lineTo(0, h - c)
      ..lineTo(0, c)
      ..close();

    // 1. ネオン発光シャドウ
    final glowPaint = Paint()
      ..color = glowColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(path, glowPaint);

    // 2. メイングラデーション枠線
    final borderGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        glowColor.withValues(alpha: 0.9),
        borderAccent.withValues(alpha: 0.6),
        Colors.white.withValues(alpha: 0.2),
        glowColor.withValues(alpha: 0.7),
      ],
      stops: const [0.0, 0.35, 0.7, 1.0],
    );

    final borderPaint = Paint()
      ..shader = borderGradient.createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, borderPaint);

    // 3. 四隅の切欠き角に設置されたメカニカルビス（ボルトアクセント）
    final boltPaint = Paint()
      ..color = glowColor.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    // 左上・右上・右下・左下の角
    final bolts = [
      Offset(c, c / 2),
      Offset(w - c, c / 2),
      Offset(w - c / 2, h - c),
      Offset(c / 2, h - c),
    ];

    for (final bolt in bolts) {
      canvas.drawCircle(bolt, 2.0, boltPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
