import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/youtube/youtube_auth.dart';
import '../../design_tokens/tokens.dart';
import '../../utils/display_error.dart';
import '../../utils/log.dart';
import '../../utils/navigation.dart';
import '../../widgets/af_loading_indicator.dart';
import '../../state/youtube_music_providers.dart';

/// WebView-based Google login screen for YouTube Music.
///
/// Opens m.youtube.com with a spoofed Chrome-Android UA to avoid Google's
/// "insecure browser" detection. Monitors CookieManager for SAPISID +
/// LOGIN_INFO to confirm successful login, then extracts dataSyncId
/// via JS injection.
class YouTubeLoginScreen extends ConsumerStatefulWidget {
  const YouTubeLoginScreen({super.key});

  @override
  ConsumerState<YouTubeLoginScreen> createState() => _YouTubeLoginScreenState();
}

class _YouTubeLoginScreenState extends ConsumerState<YouTubeLoginScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isCompleting = false;
  String? _error;
  String? _dataSyncId;

  /// Native channel to read HttpOnly cookies from android.webkit.CookieManager.
  static const _ytAuthChannel = MethodChannel('aetherfin.youtube_auth');

  // Chrome-Android UA — strips wv + Version to avoid Google's embedded browser block.
  static const _chromeUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      // JavaScript must be unrestricted — the login flow relies on JS injection
      // to extract SAPISID cookies and dataSyncId from window.yt.config_.
      // This is safe because we only load music.youtube.com (Google's domain).
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_chromeUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: _onPageStarted,
          onPageFinished: _onPageFinished,
          // Restrict navigation to YouTube/Google domains only
          onNavigationRequest: (navigationRequest) async {
            final url = navigationRequest.url;
            if (url.contains('youtube.com') || url.contains('google.com')) {
              return NavigationDecision.navigate;
            }
            afLog('youtube', 'Blocked navigation to non-YouTube URL: $url');
            return NavigationDecision.prevent;
          },
        ),
      )
      // Navigate to music.youtube.com — if already logged in, _tryCompleteLogin
      // fires immediately. If not, Google login flow starts from here.
      ..loadRequest(Uri.parse('https://music.youtube.com'));
  }

  void _onPageStarted(String url) {
    afLog('youtube', 'WebView page started: $url');
  }

  Future<void> _onPageFinished(String url) async {
    if (!mounted || _isCompleting) return;

    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }

    // Once we reach music.youtube.com, try to extract cookies + dataSyncId.
    if (url.contains('music.youtube.com')) {
      await _tryCompleteLogin();
    }

    // Also try JS extraction on any page to get dataSyncId early.
    await _extractDataSyncId();
  }

  /// Extract dataSyncId from window.yt.config_ via JS injection.
  Future<void> _extractDataSyncId() async {
    try {
      final result = await _controller.runJavaScriptReturningResult(
        "window.yt && window.yt.config_ && window.yt.config_.DATASYNC_ID || ''",
      );
      final raw = result.toString();
      final cleaned = _cleanJsString(raw);
      if (cleaned.isNotEmpty && cleaned != 'null') {
        if (cleaned.contains('||')) {
          _dataSyncId = cleaned.substringBefore('||');
        } else {
          _dataSyncId = cleaned;
        }
        afLog('youtube', 'dataSyncId extracted: $_dataSyncId');
      }
    } on Exception catch (e) {
      afLog('youtube', 'dataSyncId extraction failed', error: e);
    }
  }

  /// Attempt to complete login by reading cookies from native CookieManager.
  Future<void> _tryCompleteLogin() async {
    if (_isCompleting) return;
    _isCompleting = true;

    try {
      // Read ALL cookies (including HttpOnly) from android.webkit.CookieManager.
      final rawCookies = await _ytAuthChannel.invokeMethod<String>(
        'getCookies',
        {'url': 'https://music.youtube.com'},
      );
      if (rawCookies == null || rawCookies.isEmpty) {
        afLog('youtube', 'No cookies from CookieManager');
        if (mounted) {
          setState(() {
            _error = 'No cookies found. Please try again.';
            _isCompleting = false;
          });
        }
        return;
      }

      // Parse cookie string into map
      final cookies = <String, String>{};
      for (final part in rawCookies.split('; ')) {
        final idx = part.indexOf('=');
        if (idx > 0) {
          cookies[part.substring(0, idx)] = part.substring(idx + 1);
        }
      }

      // Check for required auth cookies
      final hasSapisid =
          cookies.containsKey('SAPISID') ||
          cookies.containsKey('__Secure-3PAPISID');
      final hasLoginInfo = cookies.containsKey('LOGIN_INFO');
      final hasSid = cookies.containsKey('SID');

      afLog(
        'youtube',
        'CookieManager cookies: ${cookies.length} '
            'SAPISID=$hasSapisid LOGIN_INFO=$hasLoginInfo SID=$hasSid',
      );

      if (!hasSapisid || !hasLoginInfo) {
        // Not logged in yet — user needs to sign in via the WebView.
        // Don't show error, just wait for them to complete sign-in.
        afLog('youtube', 'Cookies incomplete — waiting for user sign-in');
        if (mounted) {
          setState(() => _isCompleting = false);
        }
        return;
      }

      // Extract email from accounts.google.com
      String email = '';
      String? profileUrl;
      try {
        final accountInfo = await _extractAccountInfo();
        email = accountInfo.email;
        profileUrl = accountInfo.profileUrl;
      } on Exception catch (e) {
        afLog('youtube', 'Account info extraction failed', error: e);
      }

      // Save auth bundle
      final authBundle = YouTubeAuthBundle(
        cookies: cookies,
        email: email,
        displayName: email.isNotEmpty
            ? email.split('@').first
            : 'YouTube Music',
        dataSyncId: _dataSyncId,
        profileUrl: profileUrl,
      );

      await ref.read(youtubeAuthProvider.notifier).save(authBundle);
      afLog(
        'youtube',
        'Login completed: email=$email cookies=${cookies.length}',
      );

      if (mounted) {
        context.go('/home');
      }
    } on Exception catch (e, stack) {
      afLog(
        'aetherfin:error',
        'Login completion failed',
        error: e,
        stackTrace: stack,
      );
      if (mounted) {
        setState(() {
          _error = 'Login failed: ${displayError(e)}';
          _isCompleting = false;
        });
      }
    }
  }

  /// Extract email + profile picture from the current page (music.youtube.com).
  Future<_AccountInfo> _extractAccountInfo() async {
    String email = '';
    String? profileUrl;

    // Source 1: ytcfg
    try {
      final r1 = await _controller.runJavaScriptReturningResult(
        "typeof ytcfg !== 'undefined' && ytcfg.get('EMAIL') || ''",
      );
      final e1 = _cleanJsString(r1.toString());
      if (e1.contains('@')) email = e1;
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'YouTube email source 1 failed',
        error: e,
        stackTrace: stack,
      );
    }

    // Source 2: window.yt.config_.EMAIL
    if (email.isEmpty) {
      try {
        final r2 = await _controller.runJavaScriptReturningResult(
          "window.yt && window.yt.config_ && window.yt.config_.EMAIL || ''",
        );
        final e2 = _cleanJsString(r2.toString());
        if (e2.contains('@')) email = e2;
      } on Exception catch (e, stack) {
        afLog(
          'error',
          'YouTube email source 2 failed',
          error: e,
          stackTrace: stack,
        );
      }
    }

    // Source 3: Profile pic — try GAIA_ID to construct Google profile URL
    // or find img directly
    try {
      // First try: construct from GAIA_ID (most reliable)
      final rGaia = await _controller.runJavaScriptReturningResult(
        "typeof ytcfg !== 'undefined' && ytcfg.get('GAIA_ID') || ''",
      );
      final gaiaId = _cleanJsString(rGaia.toString());
      if (gaiaId.isNotEmpty) {
        profileUrl = 'https://lh3.googleusercontent.com/a-/$gaiaId=s512-c';
      }
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'YouTube GAIA ID extraction failed',
        error: e,
        stackTrace: stack,
      );
    }

    // Second try: find image in DOM
    if (profileUrl == null) {
      try {
        final r3 = await _controller.runJavaScriptReturningResult(
          "(() => { "
          "const imgs = document.querySelectorAll('img'); "
          "for (const img of imgs) { "
          "  const src = img.getAttribute('data-src') || img.src || ''; "
          "  if (src.includes('googleusercontent') || src.includes('ggpht')) return src; "
          "} "
          "return ''; })()",
        );
        final pic = _cleanJsString(r3.toString());
        if (pic.isNotEmpty && pic.startsWith('http')) {
          profileUrl = pic
              .replaceAll(RegExp(r'=s\d+(-c)?'), '=s512-c')
              .replaceAll(RegExp(r'/s\d+/'), '/s512/');
        }
      } on Exception catch (e, stack) {
        afLog(
          'error',
          'YouTube DOM image extraction failed',
          error: e,
          stackTrace: stack,
        );
      }
    }

    // Source 4: Navigate to accounts.google.com only for email
    if (email.isEmpty) {
      try {
        await _controller.loadRequest(
          Uri.parse('https://myaccount.google.com'),
        );
        await Future<void>.delayed(const Duration(seconds: 3));
        final r4 = await _controller.runJavaScriptReturningResult(
          "(() => { "
          "const all = document.querySelectorAll('*'); "
          "for (const el of all) { "
          "  if (el.children.length === 0) { "
          "    const t = (el.textContent || '').trim(); "
          "    if (/^[\\w.+-]+@[\\w.-]+\\.[a-zA-Z]{2,}\$/.test(t)) return t; "
          "  } "
          "} "
          "return ''; })()",
        );
        final e4 = _cleanJsString(r4.toString());
        if (e4.contains('@')) email = e4;

        // Also get profile pic from accounts page
        if (profileUrl == null) {
          final rPic = await _controller.runJavaScriptReturningResult(
            "(() => { "
            "const imgs = document.querySelectorAll('img'); "
            "for (const img of imgs) { "
            "  const src = img.getAttribute('data-src') || img.src || ''; "
            "  if (src.includes('googleusercontent') || src.includes('ggpht')) return src; "
            "} "
            "return ''; })()",
          );
          final pic = _cleanJsString(rPic.toString());
          if (pic.isNotEmpty && pic.startsWith('http')) {
            profileUrl = pic
                .replaceAll(RegExp(r'=s\d+(-c)?'), '=s512-c')
                .replaceAll(RegExp(r'/s\d+/'), '/s512/');
          }
        }
      } on Exception catch (e, stack) {
        afLog(
          'error',
          'YouTube account page extraction failed',
          error: e,
          stackTrace: stack,
        );
      }
    }

    return _AccountInfo(email: email, profileUrl: profileUrl);
  }

  /// Strip surrounding quotes from a JS return value.
  String _cleanJsString(String raw) {
    var result = raw.trim();
    // Strip all surrounding quote characters (single, double)
    while (result.length >= 2 &&
        ((result.startsWith("'") && result.endsWith("'")) ||
            (result.startsWith('"') && result.endsWith('"')))) {
      result = result.substring(1, result.length - 1);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        backgroundColor: AfColors.surfaceBase,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: AfColors.textPrimary),
          onPressed: () => context.safePop(),
        ),
        title: Text(
          'Sign in to YouTube Music',
          style: AfTypography.titleSmall.copyWith(color: AfColors.textPrimary),
        ),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(AfSpacing.s16),
              child: AfLoadingIndicator(),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AfSpacing.s12),
              color: AfColors.semanticError.withValues(alpha: 0.15),
              child: Text(
                _error!,
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.semanticError,
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_isLoading)
                  const Center(
                    child: AfLoadingIndicator(color: AfColors.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountInfo {
  const _AccountInfo({required this.email, this.profileUrl});
  final String email;
  final String? profileUrl;
}

/// Extension to add `substringBefore` to String.
extension _StringExt on String {
  String substringBefore(String delimiter) {
    final idx = indexOf(delimiter);
    return idx == -1 ? this : substring(0, idx);
  }
}
