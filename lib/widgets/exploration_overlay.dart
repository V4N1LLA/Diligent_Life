import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/exploration.dart';

// Pre-index at seven display scales once. Camera changes query visible buckets,
// never every historical cell. Zoomed-out buckets are approximate coverage.
class ExplorationIndex {
  ExplorationIndex(List<ExplorationCell> cells, Set<String> newIds) {
    for (final zoom in levels) {
      final rows = <int, Map<int, bool>>{};
      final shift = 17 - zoom;
      for (final cell in cells) {
        final row = rows.putIfAbsent(cell.y >> shift, () => {});
        final x = cell.x >> shift;
        row[x] = (row[x] ?? false) || newIds.contains(cell.id);
      }
      _groups[zoom] = rows;
    }
  }
  static const levels = [0, 3, 6, 9, 12, 15, 17];
  final _groups = <int, Map<int, Map<int, bool>>>{};
  List<(ExplorationCell, bool)> visible(
    double west,
    double south,
    double east,
    double north,
    double zoom,
  ) {
    var level = levels.where((v) => v <= zoom + 5).lastOrNull ?? 0;
    // FlutterMap can expose longitudes beyond +/-180 while panning the world.
    final wholeWorld = (east - west).abs() >= 360;
    west = (west + 180) % 360 - 180;
    east = (east + 180) % 360 - 180;
    late ExplorationCell nw, se;
    late List<(int, int)> ranges;
    while (true) {
      nw = ExplorationCell.at(north, west, zoom: level);
      se = ExplorationCell.at(south, east, zoom: level);
      ranges = wholeWorld
          ? [(0, (1 << level) - 1)]
          : west <= east
          ? [(nw.x, se.x)]
          : [(nw.x, (1 << level) - 1), (0, se.x)];
      final buckets =
          ranges.fold<int>(0, (n, r) => n + r.$2 - r.$1 + 1) *
          (se.y - nw.y + 1);
      // A large viewport is simplified before any potentially large loop.
      if (buckets <= 512 || level == 0) break;
      level = levels[levels.indexOf(level) - 1];
    }
    final result = <(ExplorationCell, bool)>[];
    for (var y = nw.y; y <= se.y; y++) {
      final row = _groups[level]![y];
      if (row == null) continue;
      for (final (left, right) in ranges) {
        for (var x = left; x <= right; x++) {
          final highlighted = row[x];
          if (highlighted != null) {
            result.add((ExplorationCell(x, y, zoom: level), highlighted));
          }
        }
      }
    }
    return result;
  }
}

class ExplorationOverlay extends StatefulWidget {
  const ExplorationOverlay({
    super.key,
    required this.cells,
    required this.newIds,
  });
  final List<ExplorationCell> cells;
  final Set<String> newIds;
  @override
  State<ExplorationOverlay> createState() => _ExplorationOverlayState();
}

class _ExplorationOverlayState extends State<ExplorationOverlay> {
  late ExplorationIndex _index;
  final _polygons = <String, Polygon>{};
  Brightness? _brightness;
  void _reset() {
    _index = ExplorationIndex(widget.cells, widget.newIds);
    _polygons.clear();
  }

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(ExplorationOverlay old) {
    super.didUpdateWidget(old);
    if (!identical(old.cells, widget.cells) ||
        !identical(old.newIds, widget.newIds)) {
      _reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context),
        bounds = MapCamera.of(context).visibleBounds;
    final scheme = Theme.of(context).colorScheme;
    if (_brightness != scheme.brightness) {
      _polygons.clear();
      _brightness = scheme.brightness;
    }
    final visible = _index.visible(
      bounds.west,
      bounds.south,
      bounds.east,
      bounds.north,
      camera.zoom,
    );
    return Stack(
      children: [
        PolygonLayer(
          polygons: [
            for (final (cell, fresh) in visible)
              if (cell.zoom == 17)
                _polygons.putIfAbsent(cell.id, () {
                  // Bound retained geometry when a user pans across a large history.
                  if (_polygons.length >= 1024) {
                    _polygons.remove(_polygons.keys.first);
                  }
                  final color = fresh ? scheme.tertiary : scheme.primary;
                  return Polygon(
                    points: cell.polygon,
                    color: color.withValues(alpha: .20),
                    borderColor: color.withValues(alpha: .65),
                    borderStrokeWidth: 1,
                  );
                }),
          ],
        ),
        // Aggregation marks approximate distribution, never an enormous filled
        // polygon that would falsely imply its whole area had been visited.
        CircleLayer(
          circles: [
            for (final (cell, fresh) in visible)
              if (cell.zoom != 17)
                CircleMarker(
                  point: LatLng(
                    (cell.corner(0, 0).latitude + cell.corner(1, 1).latitude) /
                        2,
                    (cell.corner(0, 0).longitude +
                            cell.corner(1, 1).longitude) /
                        2,
                  ),
                  radius: 5,
                  color: (fresh ? scheme.tertiary : scheme.primary).withValues(
                    alpha: .8,
                  ),
                ),
          ],
        ),
      ],
    );
  }
}
