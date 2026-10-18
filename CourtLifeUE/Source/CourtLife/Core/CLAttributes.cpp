#include "CLAttributes.h"

#include <algorithm>
#include <cmath>
#include <numeric>

#include "CLMath.h"

namespace courtlife {
namespace {

struct CapRule {
  float base, h, w, ws;
};

// Must stay in sync with courtlife/src/core/attributes.js (the web creator).
constexpr std::array<CapRule, kAttrCount> kCapRules = {{
    {80, 19, 6, 0},     // CloseShot
    {97, -12, -6, 4},   // DrivingLayup
    {70, 25, 2, 4},     // DrivingDunk
    {99, -10, -4, -4},  // MidRange
    {99, -16, -6, -6},  // ThreePoint
    {99, -6, 0, -3},    // FreeThrow
    {99, -26, -6, -2},  // BallHandle
    {99, -24, -10, 0},  // SpeedWithBall
    {99, -12, 0, 0},    // PassAccuracy
    {88, -6, -4, 14},   // PerimeterDefense
    {88, -10, -4, 14},  // Steal
    {62, 28, 4, 12},    // Block
    {99, -22, -12, 0},  // Speed
    {99, -24, -10, 0},  // Acceleration
    {96, -10, -14, 0},  // Vertical
    {62, 14, 24, 0},    // Strength
    {99, -4, -8, 0},    // Stamina
}};

constexpr std::array<std::string_view, kAttrCount> kNames = {
    "Close Shot", "Driving Layup", "Driving Dunk", "Mid-Range Shot", "Three-Point Shot", "Free Throw",
    "Ball Handle", "Speed With Ball", "Pass Accuracy", "Perimeter Defense", "Steal", "Block",
    "Speed", "Acceleration", "Vertical", "Strength", "Stamina"};

}  // namespace

std::string_view AttrName(Attr k) { return kNames[static_cast<int>(k)]; }

Body NormalizeBody(Body b) {
  b.heightIn = std::clamp(b.heightIn, kHeightMin, kHeightMax);
  b.weightLb = std::clamp(b.weightLb, kWeightMin, kWeightMax);
  b.wingspanIn = std::clamp(b.wingspanIn, b.heightIn + kWingspanDeltaMin, b.heightIn + kWingspanDeltaMax);
  b.build = Clamp(b.build, 0., 1.);
  return b;
}

Attributes AttributeCaps(const Body& body) {
  const float h = InvLerp(kHeightMin, kHeightMax, static_cast<float>(body.heightIn));
  const float w = InvLerp(kWeightMin, kWeightMax, static_cast<float>(body.weightLb));
  const float ws = InvLerp(kWingspanDeltaMin, kWingspanDeltaMax, static_cast<float>(body.wingspanIn - body.heightIn));
  Attributes caps{};
  for (int i = 0; i < kAttrCount; ++i) {
    const CapRule& r = kCapRules[i];
    const float cap = r.base + r.h * h + r.w * w + r.ws * ws;
    caps[i] = static_cast<int>(std::lround(Clamp(cap, 60., kAttrMax)));
  }
  return caps;
}

int PointsUsed(const Attributes& a) { return std::accumulate(a.begin(), a.end(), 0); }

Attributes LegalizeAttributes(const Attributes& a, const Body& body) {
  const Attributes caps = AttributeCaps(body);
  Attributes out{};
  for (int i = 0; i < kAttrCount; ++i) out[i] = std::clamp(a[i], kAttrMin, caps[i]);
  int over = PointsUsed(out) - kAttributeBudget;
  while (over > 0) {
    // Ties go to the first attribute, matching the JS reduce().
    auto top = std::max_element(out.begin(), out.end());
    if (*top <= kAttrMin) break;
    --*top;
    --over;
  }
  return out;
}

int SetAttribute(const Attributes& a, const Body& body, Attr key, int value) {
  const int idx = static_cast<int>(key);
  const int cap = AttributeCaps(body)[idx];
  const int others = PointsUsed(a) - a[idx];
  return std::clamp(value, kAttrMin, std::max(kAttrMin, std::min(cap, kAttributeBudget - others)));
}

int OverallRating(const Attributes& a, Position pos) {
  using A = Attr;
  std::array<float, kAttrCount> w;
  w.fill(0.5);
  auto set = [&](A k, float v) { w[static_cast<int>(k)] = v; };
  switch (pos) {
    case Position::PG:
      set(A::BallHandle, 3); set(A::PassAccuracy, 3); set(A::ThreePoint, 2); set(A::SpeedWithBall, 2);
      set(A::DrivingLayup, 1); set(A::PerimeterDefense, 1); set(A::Speed, 1);
      break;
    case Position::SG:
      set(A::ThreePoint, 3); set(A::MidRange, 2); set(A::BallHandle, 2); set(A::DrivingLayup, 1);
      set(A::PerimeterDefense, 1); set(A::Speed, 1); set(A::Steal, 1);
      break;
    case Position::SF:
      set(A::MidRange, 2); set(A::ThreePoint, 2); set(A::DrivingLayup, 2); set(A::DrivingDunk, 1);
      set(A::PerimeterDefense, 2); set(A::Vertical, 1);
      break;
    case Position::PF:
      set(A::CloseShot, 3); set(A::DrivingDunk, 2); set(A::Strength, 2); set(A::Block, 2);
      set(A::MidRange, 1); set(A::Vertical, 1);
      break;
    case Position::C:
      set(A::CloseShot, 3); set(A::Block, 3); set(A::Strength, 3); set(A::DrivingDunk, 1); set(A::Vertical, 1);
      break;
  }
  float total = 0, wsum = 0;
  for (int i = 0; i < kAttrCount; ++i) {
    total += a[i] * w[i];
    wsum += w[i];
  }
  return static_cast<int>(std::lround(total / wsum));
}

}  // namespace courtlife
