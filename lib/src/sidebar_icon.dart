import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:yaru/yaru.dart';

/// GTK's active headerbar artwork, tinted by the existing native button style.
class NativeGitSidebarIcon extends StatefulWidget {
  const NativeGitSidebarIcon({super.key});
  @override
  State<NativeGitSidebarIcon> createState() => _NativeGitSidebarIconState();
}

class _NativeGitSidebarIconState extends State<NativeGitSidebarIcon> {
  static const _channel = MethodChannel('busystack_git_flutter/icons');
  static final _revision = ValueNotifier(0);
  static bool _listening = false;
  Future<Uint8List?>? _asset;
  (int, TextDirection)? _request;
  bool get _linux => !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  @override
  void initState() {
    super.initState();
    _revision.addListener(_changed);
    if (_linux && !_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'changed') _revision.value++;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final request = (
      MediaQuery.devicePixelRatioOf(context).ceil(),
      Directionality.of(context),
    );
    if (request != _request) {
      _request = request;
      _load();
    }
  }

  void _load() {
    final request = _request;
    if (_linux && request != null) {
      _asset = _channel.invokeMethod<Uint8List>('sidebar', {
        'scale': request.$1,
        'rtl': request.$2 == TextDirection.rtl,
      });
    }
  }

  void _changed() => setState(_load);

  @override
  void dispose() {
    _revision.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Other platforms retain their existing font icon. Linux must provision
    // the real GTK artwork; a missing plugin/icon is an error, not a fallback.
    if (!_linux) return const Icon(YaruIcons.sidebar, size: 16);
    return FutureBuilder<Uint8List?>(
      future: _asset,
      builder: (context, snapshot) {
        if (snapshot.hasError ||
            (snapshot.connectionState == ConnectionState.done &&
                snapshot.data == null)) {
          throw StateError('GTK sidebar icon unavailable: ${snapshot.error}');
        }
        final bytes = snapshot.data;
        if (bytes == null) return const SizedBox.square(dimension: 16);
        return ExcludeSemantics(
          child: Image.memory(
            bytes,
            width: 16,
            height: 16,
            scale: _request!.$1.toDouble(),
            color: IconTheme.of(context).color,
            colorBlendMode: BlendMode.srcIn,
            filterQuality: FilterQuality.none,
            gaplessPlayback: true,
          ),
        );
      },
    );
  }
}
