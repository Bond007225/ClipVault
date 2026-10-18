// Engine-independent math helpers for CourtLife's gameplay core.
// This folder must not include any Unreal headers so it can be unit tested
// with a plain C++ compiler and shared with tools/servers.
#pragma once

#include <algorithm>
#include <cmath>

namespace courtlife {

constexpr double kPi = 3.14159265358979323846;

// Math runs in double precision to match the web creator's JavaScript
// exactly (a 1ms rounding difference would move the green window).
inline double Clamp(double v, double lo, double hi) { return std::min(hi, std::max(lo, v)); }
inline double Lerp(double a, double b, double t) { return a + (b - a) * t; }
inline double InvLerp(double a, double b, double v) { return a == b ? 0.0 : Clamp((v - a) / (b - a), 0.0, 1.0); }
inline double Smoothstep(double t) {
  const double x = Clamp(t, 0.0, 1.0);
  return x * x * (3.0 - 2.0 * x);
}

struct Vec2 {
  double x = 0.0;
  double z = 0.0;  // court plane uses x (sideline to sideline) and z (baseline to half court)
};

inline double Distance(Vec2 a, Vec2 b) { return std::hypot(a.x - b.x, a.z - b.z); }

}  // namespace courtlife
