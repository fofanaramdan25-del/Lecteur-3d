import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

const Color _bg = Color(0xFF0D1017);
const Color _surface = Color(0xFF171B26);
const Color _accent = Color(0xFF7AA2FF);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const LecteurApp());
}

String _fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

String _title(AssetEntity a) {
  final String t = a.title ?? 'Vidéo';
  return t.replaceAll(RegExp(r'\.[^.]+$'), '');
}

class LecteurApp extends StatelessWidget {
  const LecteurApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lecteur Diaporama 3D',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.dark,
        ),
      ),
      home: const GalleryPage(),
    );
  }
}

// ---------------------------------------------------------------------------
// Galerie : toutes les vidéos du téléphone, en carrousel 3D
// ---------------------------------------------------------------------------

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  final PageController _pc = PageController(viewportFraction: 0.62);
  final Map<String, Future<Uint8List?>> _thumbs = {};
  List<AssetEntity> _videos = [];
  bool _loading = true;
  bool _denied = false;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _denied = false;
    });
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!(ps.isAuth || ps == PermissionState.limited)) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _denied = true;
      });
      return;
    }
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      onlyAll: true,
    );
    List<AssetEntity> list = [];
    if (paths.isNotEmpty) {
      final int count = await paths.first.assetCountAsync;
      list = await paths.first.getAssetListRange(start: 0, end: count);
    }
    if (!mounted) return;
    setState(() {
      _videos = list;
      _loading = false;
      _current = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pc.hasClients && _videos.isNotEmpty) _pc.jumpToPage(0);
    });
  }

  Future<void> _open(AssetEntity a) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerPage(asset: a)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Lecteur Diaporama 3D',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Actualiser',
                  ),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_denied) {
      return _message(
        "L'accès aux vidéos est nécessaire pour afficher ta galerie.",
        'Ouvrir les réglages',
        () => PhotoManager.openSetting(),
      );
    }
    if (_videos.isEmpty) {
      return _message('Aucune vidéo trouvée sur ce téléphone.', 'Actualiser', _load);
    }
    return _carousel();
  }

  Widget _message(String text, String label, VoidCallback onPressed) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onPressed, child: Text(label)),
          ],
        ),
      ),
    );
  }

  Widget _carousel() {
    final double w = MediaQuery.of(context).size.width;
    final double h = w * 0.62 * 9 / 16 + 60;
    final AssetEntity cur = _videos[_current.clamp(0, _videos.length - 1)];
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: h,
          child: PageView.builder(
            controller: _pc,
            itemCount: _videos.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) => _card(i),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _title(cur),
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_fmt(cur.videoDuration)}  ·  ${_current + 1} / ${_videos.length}',
          style: const TextStyle(fontSize: 13, color: Colors.white54),
        ),
        const SizedBox(height: 14),
        const Text(
          'Touche la vidéo du centre pour la lire',
          style: TextStyle(fontSize: 12, color: Colors.white38),
        ),
      ],
    );
  }

  Widget _card(int i) {
    final AssetEntity a = _videos[i];
    final Future<Uint8List?> future = _thumbs.putIfAbsent(
      a.id,
      () => a.thumbnailDataWithSize(const ThumbnailSize(480, 270)),
    );
    final Widget body = GestureDetector(
      onTap: () {
        if (i == _current) {
          _open(a);
        } else {
          _pc.animateToPage(
            i,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<Uint8List?>(
                    future: future,
                    builder: (context, snap) {
                      final Uint8List? d = snap.data;
                      if (d == null) return Container(color: _surface);
                      return Image.memory(d, fit: BoxFit.cover, gaplessPlayback: true);
                    },
                  ),
                  Container(color: Colors.black.withAlpha(i == _current ? 0 : 110)),
                  if (i == _current)
                    const Center(
                      child: Icon(Icons.play_circle_outline, size: 44, color: Colors.white70),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: _pc,
      child: body,
      builder: (context, child) {
        double page = _pc.initialPage.toDouble();
        if (_pc.hasClients && _pc.position.haveDimensions) {
          page = _pc.page ?? page;
        }
        final double d = (i - page).clamp(-2.0, 2.0);
        final double ad = d.abs();
        final Matrix4 m = Matrix4.identity()
          ..setEntry(3, 2, 0.0014)
          ..multiply(Matrix4.translationValues(0.0, 0.0, -ad * 140.0))
          ..multiply(Matrix4.rotationY(d * -0.75));
        return Opacity(
          opacity: (1 - ad * 0.28).clamp(0.2, 1.0),
          child: Transform(alignment: Alignment.center, transform: m, child: child),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Lecteur plein écran : gestes, reprise, son, vitesse, rotation
// ---------------------------------------------------------------------------

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.asset});

  final AssetEntity asset;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  static const List<double> _rates = [0.5, 1.0, 1.5, 2.0];

  VideoPlayerController? _c;
  String? _error;
  bool _uiVisible = true;
  bool _muted = false;
  bool _landscape = false;
  double _rate = 1.0;
  String? _hint;
  bool _holdActive = false;
  bool _holdWasPlaying = true;
  Timer? _uiTimer;
  Timer? _hintTimer;
  Timer? _saveTimer;
  Timer? _rewTimer;

  String get _key => 'pos_${widget.asset.id}';

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    _init();
  }

  Future<void> _init() async {
    try {
      final file = await widget.asset.file;
      if (file == null) {
        if (mounted) setState(() => _error = "Impossible d'ouvrir cette vidéo.");
        return;
      }
      final VideoPlayerController c = VideoPlayerController.file(file);
      await c.initialize();
      final prefs = await SharedPreferences.getInstance();
      final int saved = prefs.getInt(_key) ?? 0;
      if (saved > 0 && saved < c.value.duration.inMilliseconds - 1000) {
        await c.seekTo(Duration(milliseconds: saved));
      }
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(_onTick);
      setState(() => _c = c);
      await _applyOrientation(c.value.aspectRatio > 1);
      await c.play();
      _scheduleHide();
      _saveTimer = Timer.periodic(const Duration(seconds: 2), (_) => _savePos());
    } catch (e) {
      if (mounted) setState(() => _error = 'Impossible de lire cette vidéo.');
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Future<void> _applyOrientation(bool land) async {
    _landscape = land;
    await SystemChrome.setPreferredOrientations(
      land
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp],
    );
    if (mounted) setState(() {});
  }

  Future<void> _savePos() async {
    final VideoPlayerController? c = _c;
    if (c == null || !c.value.isInitialized) return;
    final int p = c.value.position.inMilliseconds;
    final int d = c.value.duration.inMilliseconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, p > d - 1000 ? 0 : p);
  }

  // --- Interface qui apparait et disparait ---------------------------------

  void _showUi() {
    if (!_uiVisible) setState(() => _uiVisible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _uiTimer?.cancel();
    final c = _c;
    if (c == null || !c.value.isPlaying || _holdActive) return;
    _uiTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _uiVisible = false);
    });
  }

  void _toggleUi() {
    if (_uiVisible) {
      _uiTimer?.cancel();
      setState(() => _uiVisible = false);
    } else {
      _showUi();
    }
  }

  void _showHint(String text, int ms) {
    _hintTimer?.cancel();
    setState(() => _hint = text);
    if (ms > 0) {
      _hintTimer = Timer(Duration(milliseconds: ms), () {
        if (mounted) setState(() => _hint = null);
      });
    }
  }

  void _hideHint() {
    _hintTimer?.cancel();
    if (mounted) setState(() => _hint = null);
  }

  // --- Commandes ------------------------------------------------------------

  void _seekBy(Duration delta) {
    final VideoPlayerController? c = _c;
    if (c == null) return;
    Duration t = c.value.position + delta;
    if (t < Duration.zero) t = Duration.zero;
    if (t > c.value.duration) t = c.value.duration;
    c.seekTo(t);
  }

  void _togglePlay() {
    final VideoPlayerController? c = _c;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
      _showHint('❚❚  Pause', 700);
    } else {
      if (c.value.position >= c.value.duration - const Duration(milliseconds: 300)) {
        c.seekTo(Duration.zero);
      }
      c.play();
      _showHint('▶  Lecture', 700);
    }
    _showUi();
  }

  void _cycleRate() {
    final int i = _rates.indexOf(_rate);
    _rate = _rates[(i + 1) % _rates.length];
    _c?.setPlaybackSpeed(_rate);
    setState(() {});
    _showUi();
  }

  void _toggleMute() {
    _muted = !_muted;
    _c?.setVolume(_muted ? 0.0 : 1.0);
    setState(() {});
    _showUi();
  }

  void _startHold(bool forward) {
    final VideoPlayerController? c = _c;
    if (c == null) return;
    _holdActive = true;
    _holdWasPlaying = c.value.isPlaying;
    _uiTimer?.cancel();
    setState(() => _uiVisible = false);
    if (forward) {
      c.setPlaybackSpeed(2.0);
      c.play();
      _showHint('▶▶  2×', 0);
    } else {
      c.pause();
      _showHint('◀◀  2×', 0);
      _rewTimer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _seekBy(const Duration(milliseconds: -250)),
      );
    }
  }

  void _endHold() {
    if (!_holdActive) return;
    _holdActive = false;
    _rewTimer?.cancel();
    _rewTimer = null;
    final VideoPlayerController? c = _c;
    if (c != null) {
      c.setPlaybackSpeed(_rate);
      if (_holdWasPlaying) {
        c.play();
      } else {
        c.pause();
      }
    }
    _hideHint();
    _showUi();
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _hintTimer?.cancel();
    _saveTimer?.cancel();
    _rewTimer?.cancel();
    final VideoPlayerController? c = _c;
    if (c != null) {
      _savePos();
      c.removeListener(_onTick);
      c.dispose();
    }
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  // --- Affichage ------------------------------------------------------------

  Widget _zone(
    int flex, {
    required VoidCallback onTap,
    VoidCallback? onDouble,
    VoidCallback? onHoldStart,
  }) {
    return Expanded(
      flex: flex,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onDoubleTap: onDouble,
        onLongPressStart: onHoldStart == null ? null : (_) => onHoldStart(),
        onLongPressEnd: onHoldStart == null ? null : (_) => _endHold(),
        onLongPressCancel: onHoldStart == null ? null : _endHold,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? c = _c;
    return Scaffold(
      backgroundColor: Colors.black,
      body: _error != null
          ? _errorView()
          : (c == null || !c.value.isInitialized)
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: AspectRatio(
                        aspectRatio: c.value.aspectRatio,
                        child: VideoPlayer(c),
                      ),
                    ),
                    Row(
                      children: [
                        _zone(
                          32,
                          onTap: _toggleUi,
                          onDouble: () {
                            _seekBy(const Duration(seconds: -10));
                            _showHint('◀◀  −10 s', 600);
                          },
                          onHoldStart: () => _startHold(false),
                        ),
                        _zone(36, onTap: _togglePlay),
                        _zone(
                          32,
                          onTap: _toggleUi,
                          onDouble: () {
                            _seekBy(const Duration(seconds: 10));
                            _showHint('▶▶  +10 s', 600);
                          },
                          onHoldStart: () => _startHold(true),
                        ),
                      ],
                    ),
                    if (_hint != null)
                      Align(
                        alignment: const Alignment(0, -0.6),
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(130),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _hint!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    _overlay(c),
                  ],
                ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error!, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Retour'),
          ),
        ],
      ),
    );
  }

  Widget _overlay(VideoPlayerController c) {
    final Duration pos = c.value.position;
    final Duration dur = c.value.duration;
    final int maxMs = dur.inMilliseconds <= 0 ? 1 : dur.inMilliseconds;
    final double v = (pos.inMilliseconds / maxMs).clamp(0.0, 1.0);
    final EdgeInsets pad = MediaQuery.of(context).padding;
    const TextStyle small = TextStyle(color: Colors.white70, fontSize: 11);
    final String rateLabel =
        _rate == _rate.roundToDouble() ? '${_rate.toInt()}×' : '$_rate×';

    return AnimatedOpacity(
      opacity: _uiVisible ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      child: IgnorePointer(
        ignoring: !_uiVisible,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(4, pad.top + 4, 12, 18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xB3000000), Color(0x00000000)],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        _title(widget.asset),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(16, 26, 16, pad.bottom + 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xB3000000), Color(0x00000000)],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(_fmt(pos), style: small),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                              overlayShape: SliderComponentShape.noOverlay,
                              activeTrackColor: _accent,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: _accent,
                            ),
                            child: Slider(
                              value: v,
                              onChangeStart: (_) => _uiTimer?.cancel(),
                              onChanged: (x) =>
                                  c.seekTo(Duration(milliseconds: (x * maxMs).round())),
                              onChangeEnd: (_) => _showUi(),
                            ),
                          ),
                        ),
                        Text(_fmt(dur), style: small),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: () {
                            _seekBy(const Duration(seconds: -10));
                            _showUi();
                          },
                          icon: const Icon(Icons.replay_10, color: Colors.white),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: _accent),
                          ),
                          child: IconButton(
                            onPressed: _togglePlay,
                            icon: Icon(
                              c.value.isPlaying ? Icons.pause : Icons.play_arrow,
                              color: _accent,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            _seekBy(const Duration(seconds: 10));
                            _showUi();
                          },
                          icon: const Icon(Icons.forward_10, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _cycleRate,
                          child: Text(rateLabel, style: const TextStyle(color: Colors.white)),
                        ),
                        IconButton(
                          onPressed: _toggleMute,
                          icon: Icon(
                            _muted ? Icons.volume_off : Icons.volume_up,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            _applyOrientation(!_landscape);
                            _showUi();
                          },
                          icon: const Icon(Icons.screen_rotation, color: Colors.white),
                        ),
                      ],
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
