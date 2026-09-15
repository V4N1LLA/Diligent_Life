import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/exercise_session.dart';
import '../utils/gps.dart';

Color speedColor(double kmh) => kmh < 4
    ? const Color(0xff527d6b)
    : kmh < 7
    ? const Color(0xff527fa3)
    : const Color(0xff8560aa);
LatLng routeLocation(RoutePoint p) => LatLng(p.latitude, p.longitude);

class ExerciseRoute extends StatefulWidget {
  const ExerciseRoute({
    super.key,
    required this.points,
    this.currentPosition,
    this.selectedPoint,
    this.sections,
    this.selectedSection,
    this.live = false,
    this.overview = false,
    this.interactive = true,
    this.private = false,
    this.height = 320,
    this.tileProvider,
  });
  final List<RoutePoint> points;
  final RoutePoint? currentPosition;
  final RoutePoint? selectedPoint;
  final List<SpeedSection>? sections;
  final SpeedSection? selectedSection;
  final bool live, interactive, private, overview;
  final double height;
  // Injectable for deterministic, offline map tests.
  final TileProvider? tileProvider;
  @override
  State<ExerciseRoute> createState() => ExerciseRouteState();
}

class ExerciseRouteState extends State<ExerciseRoute> {
  final _controller = MapController();
  final _boundary = GlobalKey();
  final _tiles = <TileImage>{};
  bool _ready = false, _follow = true, _failed = false;
  int _retry = 0;
  TileProvider? _provider;
  TileProvider get _tileProvider => _provider ??=
      widget.tileProvider ??
      NetworkTileProvider(
        cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
          maxCacheSize: 64 * 1024 * 1024,
        ),
      );
  late List<SpeedSection> _speeds;
  @override
  void initState() {
    super.initState();
    _speeds = widget.overview
        ? []
        : (widget.sections ?? speedSections(widget.points));
  }

  @override
  void didUpdateWidget(ExerciseRoute oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.points.isEmpty && widget.currentPosition == null) {
      _ready = false;
      _provider = null;
      _tiles.clear();
    }
    if (_ready &&
        widget.selectedPoint != null &&
        oldWidget.selectedPoint != widget.selectedPoint) {
      _controller.move(
        routeLocation(widget.selectedPoint!),
        _controller.camera.zoom,
      );
    }
    if (oldWidget.sections != widget.sections) {
      _speeds = widget.overview
          ? []
          : (widget.sections ?? speedSections(widget.points));
    }
    if (oldWidget.points.length != widget.points.length ||
        oldWidget.points.firstOrNull != widget.points.firstOrNull ||
        oldWidget.points.lastOrNull != widget.points.lastOrNull) {
      _speeds = widget.overview
          ? []
          : (widget.sections ?? speedSections(widget.points));
      if (!widget.live) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fit();
        });
      }
    }
    if (_ready &&
        widget.live &&
        _follow &&
        widget.currentPosition != null &&
        oldWidget.currentPosition != widget.currentPosition) {
      _controller.move(
        routeLocation(widget.currentPosition!),
        _controller.camera.zoom,
      );
    }
  }

  void _fit() {
    if (!_ready || widget.points.isEmpty) return;
    if (widget.points.length == 1) {
      _controller.move(routeLocation(widget.points.first), 16);
    } else {
      _controller.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(
            widget.points.map(routeLocation).toList(),
          ),
          padding: const EdgeInsets.all(40),
          maxZoom: 17,
        ),
      );
    }
  }

  Future<ui.Image> capture() async {
    // Export only a fully loaded, fixed private viewport. No blank-map cards.
    final previewContext = _boundary.currentContext;
    if (previewContext == null) throw StateError('Map is not mounted');
    await Scrollable.ensureVisible(
      previewContext,
      alignment: .15,
      duration: const Duration(milliseconds: 250),
    );
    await WidgetsBinding.instance.endOfFrame;
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (mounted) {
      _tiles.removeWhere((t) => t.cancelLoading.isCompleted);
      if (_tiles.any((t) => t.loadError)) {
        throw StateError('Map tiles unavailable');
      }
      if (_tiles.isNotEmpty && _tiles.every((t) => t.readyToDisplay)) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) throw StateError('Map closed');
        final boundary =
            _boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        return boundary.toImage(pixelRatio: 3);
      }
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Map loading');
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError('Map closed');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _tiles.removeWhere((tile) => tile.cancelLoading.isCompleted);
    final points = widget.points;
    final position = widget.currentPosition;
    if (points.isEmpty && position == null) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              widget.live
                  ? 'GPS 위치를 기다리고 있어요.\n위치를 받으면 지도가 여기에 표시돼요.'
                  : widget.private
                  ? '위치 보호를 위해 경로를 모두 숨겼어요.'
                  : '저장된 경로가 없어요.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final lines = <Polyline>[];
    var group = <LatLng>[];
    for (var i = 0; i < points.length; i++) {
      if (i > 0 && points[i].segment != points[i - 1].segment) {
        if (group.length > 1) {
          lines.add(
            Polyline(
              points: group,
              color: const Color(0xff527d6b),
              strokeWidth: 5,
            ),
          );
        }
        group = [];
      }
      group.add(routeLocation(points[i]));
    }
    if (group.length > 1) {
      lines.add(
        Polyline(points: group, color: const Color(0xff527d6b), strokeWidth: 5),
      );
    }
    lines.addAll(
      _speeds.map(
        (s) => Polyline(
          points: s.points.map(routeLocation).toList(),
          color: speedColor(s.kmh),
          strokeWidth: 5,
        ),
      ),
    );
    if (widget.selectedSection case final selected?) {
      lines.add(
        Polyline(
          points: selected.points.map(routeLocation).toList(),
          color: Theme.of(context).colorScheme.onSurface,
          strokeWidth: 9,
        ),
      );
      lines.add(
        Polyline(
          points: selected.points.map(routeLocation).toList(),
          color: speedColor(selected.kmh),
          strokeWidth: 5,
        ),
      );
    }
    Marker marker(RoutePoint p, IconData icon, Color color, String label) =>
        Marker(
          point: routeLocation(p),
          width: 34,
          height: 34,
          child: Tooltip(
            message: label,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: Icon(icon, color: Colors.white, size: 19),
            ),
          ),
        );
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                key: _boundary,
                child: FlutterMap(
                  mapController: _controller,
                  options: MapOptions(
                    initialCenter: routeLocation(position ?? points.first),
                    initialZoom: 16,
                    initialCameraFit: !widget.live && points.length > 1
                        ? CameraFit.bounds(
                            bounds: LatLngBounds.fromPoints(
                              points.map(routeLocation).toList(),
                            ),
                            padding: const EdgeInsets.all(40),
                            maxZoom: 17,
                          )
                        : null,
                    onMapReady: () => _ready = true,
                    onPositionChanged: (_, gesture) {
                      if (gesture && _follow) setState(() => _follow = false);
                    },
                    interactionOptions: InteractionOptions(
                      flags: widget.interactive
                          ? InteractiveFlag.all & ~InteractiveFlag.rotate
                          : InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      key: ValueKey(_retry),
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.v4n1lla.diligent_life',
                      tileProvider: _tileProvider,
                      maxNativeZoom: 19,
                      panBuffer: 0,
                      tileDisplay: const TileDisplay.instantaneous(),
                      tileBuilder: (context, child, tile) {
                        _tiles.add(tile);
                        return child;
                      },
                      errorTileCallback: (_, error, stack) {
                        if (!_failed) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() => _failed = true);
                          });
                        }
                      },
                    ),
                    PolylineLayer(polylines: lines),
                    MarkerLayer(
                      markers: [
                        if (widget.selectedPoint != null)
                          marker(
                            widget.selectedPoint!,
                            Icons.speed,
                            const Color(0xff8560aa),
                            '선택한 속도 구간',
                          ),
                        if (points.isNotEmpty && !widget.overview)
                          marker(
                            points.first,
                            Icons.play_arrow,
                            const Color(0xff527d6b),
                            widget.private ? '공개 경로 시작' : '시작',
                          ),
                        if (!widget.live &&
                            !widget.overview &&
                            points.length > 1)
                          marker(
                            points.last,
                            Icons.flag,
                            const Color(0xff8560aa),
                            widget.private ? '공개 경로 끝' : '도착',
                          ),
                        if (widget.live && position != null)
                          marker(
                            position,
                            Icons.my_location,
                            const Color(0xff527fa3),
                            '최근 수신 위치',
                          ),
                      ],
                    ),
                    const Align(
                      alignment: Alignment.bottomRight,
                      child: ColoredBox(
                        color: Color(0xeeffffff),
                        child: Padding(
                          padding: EdgeInsets.all(4),
                          child: Text(
                            '© OpenStreetMap contributors\nopenstreetmap.org/copyright',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xff263c33),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.live)
              Positioned(
                top: 12,
                right: 12,
                child: IconButton.filledTonal(
                  tooltip: _follow ? '현재 위치 따라가는 중' : '현재 위치 따라가기',
                  onPressed: () {
                    setState(() => _follow = true);
                    if (_ready && position != null) {
                      _controller.move(routeLocation(position), 16);
                    }
                  },
                  icon: Icon(_follow ? Icons.gps_fixed : Icons.gps_not_fixed),
                ),
              ),
            if (_failed)
              Positioned(
                left: 8,
                top: 8,
                right: widget.live ? 64 : 8,
                child: Material(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.surface,
                  child: TextButton(
                    onPressed: () => setState(() {
                      _failed = false;
                      _tiles.clear();
                      _provider = null;
                      _retry++;
                    }),
                    child: const Text('지도를 불러오지 못했어요 · 재시도'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
