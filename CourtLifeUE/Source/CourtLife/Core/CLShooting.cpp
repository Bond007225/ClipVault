#include "CLShooting.h"

#include <cmath>

namespace courtlife {

// Must stay in sync with courtlife/src/core/shooting.js.

bool IsThree(Vec2 s) {
  if (std::fabs(s.x) >= kCornerThreeXFt && s.z < kBaselineZFt + 14.) return true;
  return std::hypot(s.x, s.z) > kThreePtRadiusFt;
}

ReleaseResult GradeRelease(const ShotProfile& p, float heldMs) {
  const float delta = heldMs - p.releaseTimeMs;
  const float half = p.greenWindowMs / 2.;
  const float a = std::fabs(delta);
  ReleaseGrade g;
  if (a <= half) g = ReleaseGrade::Green;
  else if (a <= half + 70.) g = delta < 0 ? ReleaseGrade::SlightlyEarly : ReleaseGrade::SlightlyLate;
  else g = delta < 0 ? ReleaseGrade::Early : ReleaseGrade::Late;
  return {g, delta};
}

float ContestLevel(float defenderDistFt, int defenderHeightIn, float shooterResist) {
  if (defenderDistFt < 0) return 0;
  const float closeness = InvLerp(7., 1.5, defenderDistFt);
  const float length = Lerp(0.8, 1.2, InvLerp(72., 86., static_cast<float>(defenderHeightIn)));
  return Clamp(closeness * length * (1. - shooterResist * 0.5), 0., 1.);
}

float MakeProbability(ReleaseGrade grade, int rating, float distanceFt, float contest) {
  const float range = InvLerp(8., 30., distanceFt);
  if (grade == ReleaseGrade::Green) return Clamp(1. - std::fmax(0., contest - 0.7) * 1.5, 0.5, 1.);
  if (grade == ReleaseGrade::Early || grade == ReleaseGrade::Late) return Clamp(0.08 - contest * 0.05, 0.01, 0.1);
  const float skill = InvLerp(40., 99., static_cast<float>(rating));
  const float base = Lerp(0.3, 0.62, skill) - range * 0.2;
  return Clamp(base - contest * 0.35, 0.03, 0.75);
}

int ShotRating(const Attributes& a, float distanceFt, bool three) {
  if (three) return Get(a, Attr::ThreePoint);
  if (distanceFt < 8.) return Get(a, Attr::CloseShot);
  return Get(a, Attr::MidRange);
}

}  // namespace courtlife
