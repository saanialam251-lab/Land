import 'dart:math' as math;
import 'dart:typed_data';

/// A detected corner, in normalised IMAGE coordinates (0..1).
class Corner {
  final double x, y, score;
  const Corner(this.x, this.y, this.score);
}

class DetectResult {
  final List<Corner> corners;
  final double brightness; // 0..255 mean luma
  const DetectResult(this.corners, this.brightness);
}

/// Tiny Harris corner detector that runs on a down-sampled luma plane.
/// Cheap enough to run ~4 times per second on the UI isolate.
class CornerDetector {
  static DetectResult detect(Uint8List luma, int w, int h, int stride) {
    final step = math.max(1, w ~/ 96);
    final gw = w ~/ step, gh = h ~/ step;
    if (gw < 8 || gh < 8) return const DetectResult([], 128);

    final g = Float32List(gw * gh);
    double sum = 0;
    for (var y = 0; y < gh; y++) {
      final row = (y * step) * stride;
      for (var x = 0; x < gw; x++) {
        final idx = row + x * step;
        final v = idx < luma.length ? luma[idx].toDouble() : 0.0;
        g[y * gw + x] = v;
        sum += v;
      }
    }
    final brightness = sum / (gw * gh);

    final ix = Float32List(gw * gh);
    final iy = Float32List(gw * gh);
    for (var y = 1; y < gh - 1; y++) {
      for (var x = 1; x < gw - 1; x++) {
        final i = y * gw + x;
        ix[i] = g[i + 1] - g[i - 1];
        iy[i] = g[i + gw] - g[i - gw];
      }
    }

    final r = Float32List(gw * gh);
    var maxR = 0.0;
    for (var y = 2; y < gh - 2; y++) {
      for (var x = 2; x < gw - 2; x++) {
        var sxx = 0.0, syy = 0.0, sxy = 0.0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final j = (y + dy) * gw + (x + dx);
            final a = ix[j], b = iy[j];
            sxx += a * a;
            syy += b * b;
            sxy += a * b;
          }
        }
        final det = sxx * syy - sxy * sxy;
        final tr = sxx + syy;
        final v = det - 0.04 * tr * tr;
        r[y * gw + x] = v;
        if (v > maxR) maxR = v;
      }
    }
    if (maxR <= 0) return DetectResult(const [], brightness);

    final thr = maxR * 0.06;
    final cand = <Corner>[];
    for (var y = 3; y < gh - 3; y++) {
      for (var x = 3; x < gw - 3; x++) {
        final v = r[y * gw + x];
        if (v < thr) continue;
        var isMax = true;
        for (var dy = -2; dy <= 2 && isMax; dy++) {
          for (var dx = -2; dx <= 2; dx++) {
            if (dx == 0 && dy == 0) continue;
            if (r[(y + dy) * gw + (x + dx)] > v) {
              isMax = false;
              break;
            }
          }
        }
        if (isMax) {
          cand.add(Corner((x * step + step / 2) / w, (y * step + step / 2) / h, v / maxR));
        }
      }
    }
    cand.sort((a, b) => b.score.compareTo(a.score));
    final out = <Corner>[];
    for (final c in cand) {
      var ok = true;
      for (final o in out) {
        final dx = (o.x - c.x) * w / step, dy = (o.y - c.y) * h / step;
        if (dx * dx + dy * dy < 25) {
          ok = false;
          break;
        }
      }
      if (ok) out.add(c);
      if (out.length >= 14) break;
    }
    return DetectResult(out, brightness);
  }
}
