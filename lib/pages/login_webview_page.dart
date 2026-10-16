import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../providers/auth_state.dart';
import '../theme/app_colors.dart';

class LoginWebviewPage extends ConsumerStatefulWidget {
  final String source;
  final String title;
  final String loginUrl;
  final String cookieUrl;
  final List<String> requiredCookieKeys;

  const LoginWebviewPage({
    super.key,
    required this.source,
    required this.title,
    required this.loginUrl,
    required this.cookieUrl,
    required this.requiredCookieKeys,
  });

  @override
  ConsumerState<LoginWebviewPage> createState() => _LoginWebviewPageState();
}

class _LoginWebviewPageState extends ConsumerState<LoginWebviewPage> {
  bool _loading = true;
  bool _checking = false;

  static const _mobileUA =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static const _desktopUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  String get _userAgent {
    switch (widget.source) {
      case 'qq':
      case 'kugou':
        return _desktopUA;
      default:
        return _mobileUA;
    }
  }

  UserPreferredContentMode get _contentMode {
    switch (widget.source) {
      case 'qq':
      case 'kugou':
        return UserPreferredContentMode.DESKTOP;
      default:
        return UserPreferredContentMode.RECOMMENDED;
    }
  }

  Future<void> _checkLogin() async {
    if (_checking) return;
    _checking = true;
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(widget.cookieUrl),
      );

      if (cookies.isEmpty) {
        _showTip('没有拿到任何 Cookie，请先在下方页面完成登录');
        return;
      }

      final map = {for (final c in cookies) c.name: c.value};
      final missing = widget.requiredCookieKeys
          .where((k) => (map[k] ?? '').isEmpty)
          .toList();

      if (missing.isNotEmpty) {
        _showTip('还没登录成功\n缺少字段: ${missing.join("、")}');
        return;
      }

      final cookieStr = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      await ref.read(authProvider.notifier).save(widget.source, cookieStr);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      print('❌ 抓 cookie 失败: $e');
      _showTip('抓取失败: $e');
    } finally {
      _checking = false;
    }
  }

  void _showTip(String msg) {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(msg),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.title),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minSize: 0,
          onPressed: _checkLogin,
          child: const Text(
            '完成',
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      // ★ 关键：SafeArea 包住整个 Stack
      //   top: true  → child 从导航栏下方开始（避开状态栏 + 导航栏）
      //   bottom: true → child 到手势条上方结束
      child: SafeArea(
        top: true,
        bottom: true,
        child: Stack(
          children: [
            // WebView 撑满 SafeArea 内部
            Positioned.fill(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(widget.loginUrl)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  sharedCookiesEnabled: true,
                  thirdPartyCookiesEnabled: true,
                  useShouldOverrideUrlLoading: false,
                  userAgent: _userAgent,
                  preferredContentMode: _contentMode,
                  supportZoom: true,
                  builtInZoomControls: true,
                  displayZoomControls: false,
                  useHybridComposition: true,
                  allowsInlineMediaPlayback: true,
                  mediaPlaybackRequiresUserGesture: false,
                ),
                onLoadStart: (_, __) {
                  if (mounted) setState(() => _loading = true);
                },
                onLoadStop: (_, __) {
                  if (mounted) setState(() => _loading = false);
                },
              ),
            ),

            // 顶部 loading 指示器（相对 SafeArea 内部，导航栏下方 12px）
            if (_loading)
              const Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Center(child: CupertinoActivityIndicator()),
              ),

            // 底部提示卡片（相对 SafeArea 内部，手势条上方 20px）
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: CupertinoColors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '在下方页面登录，成功后点右上角「完成」',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '需要的凭证：${widget.requiredCookieKeys.join("、")}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}