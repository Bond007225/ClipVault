#include "CLFinishing.h"

#include <algorithm>
#include <cmath>

#include "CLMath.h"

namespace courtlife {

// Must stay in sync with courtlife/src/core/finishing.js.

namespace {
double SpeedFactor(double speedFtPerSec) { return InvLerp(4., 14., speedFtPerSec); }

struct FinishTiming {
  double gatherMs, airMs, releaseT, jump;
};
constexpr FinishTiming kLayupTiming{260., 640., 0.62, 0.85};
constexpr FinishTiming kDunkTiming{300., 700., 0.58, 1.0};
}  // namespace

double DunkReachIn(int heightIn, int vertical, double speedFtPerSec) {
  const double standingReach = heightIn * 1.33;
  const double jump = Lerp(16., 40., InvLerp(25., 99., vertical));
  return standingReach + jump + SpeedFactor(speedFtPerSec) * 4.;
}

double LayupRangeFt(double speedFtPerSec) {
  return Lerp(6., kFinishMaxRangeFt, InvLerp(2., 8., speedFtPerSec));
}

double DunkRangeFt(int drivingDunk, double speedFtPerSec) {
  return Lerp(3., 7., InvLerp(kMinDunkRating, 99., drivingDunk)) + SpeedFactor(speedFtPerSec) * 1.5;
}

FinishType ChooseFinish(const FinishInput& in) {
  if (!(in.distanceFt <= kFinishMaxRangeFt)) return FinishType::None;
  const bool canDunk = in.drivingDunk >= kMinDunkRating &&
                       in.distanceFt <= DunkRangeFt(in.drivingDunk, in.speedFtPerSec) &&
                       DunkReachIn(in.heightIn, in.vertical, in.speedFtPerSec) >= kRimHeightIn + kDunkClearanceIn;
  // Attacking downhill favors throwing it down over laying it in.
  const double dunkPreference = in.drivingDunk + SpeedFactor(in.speedFtPerSec) * 20.;
  if (canDunk && dunkPreference >= in.drivingLayup) return FinishType::Dunk;
  if (in.distanceFt <= LayupRangeFt(in.speedFtPerSec)) return FinishType::Layup;
  return FinishType::None;
}

FinishType ChooseFinish(double distanceFt, double speedFtPerSec, const Attributes& a, int heightIn) {
  FinishInput in;
  in.distanceFt = distanceFt;
  in.speedFtPerSec = speedFtPerSec;
  in.closeShot = Get(a, Attr::CloseShot);
  in.drivingLayup = Get(a, Attr::DrivingLayup);
  in.drivingDunk = Get(a, Attr::DrivingDunk);
  in.vertical = Get(a, Attr::Vertical);
  in.heightIn = heightIn;
  return ChooseFinish(in);
}

int FinishRating(const Attributes& a, FinishType type, double distanceFt) {
  if (type == FinishType::Dunk) return Get(a, Attr::DrivingDunk);
  return distanceFt <= 4. ? std::max(Get(a, Attr::CloseShot), Get(a, Attr::DrivingLayup)) : Get(a, Attr::DrivingLayup);
}

FinishProfile ComputeFinishProfile(FinishType type, const FinishContext& ctx) {
  const bool dunk = type == FinishType::Dunk;
  const FinishTiming& t = dunk ? kDunkTiming : kLayupTiming;
  const double distanceFt = Clamp(ctx.distanceFt, 0., kFinishMaxRangeFt);

  FinishProfile p;
  p.type = dunk ? FinishType::Dunk : FinishType::Layup;
  p.gatherMs = std::round(t.gatherMs + distanceFt * 12.);
  p.durationMs = p.gatherMs + t.airMs;
  p.releaseTimeMs = std::round(p.gatherMs + t.airMs * t.releaseT);
  p.releaseT = p.releaseTimeMs / p.durationMs;
  p.greenWindowMs = std::round(Lerp(20., 60., InvLerp(40., 99., ctx.rating)));
  p.jumpFt = t.jump * Lerp(1.2, 3.0, InvLerp(25., 99., ctx.vertical));
  p.releaseHeightFt = (ctx.heightIn * 1.33) / 12. + p.jumpFt;
  p.contestResist = Clamp(InvLerp(9., 12.5, p.releaseHeightFt) * 0.7 + (dunk ? 0.2 : 0.), 0., 1.);
  return p;
}

double FinishMakeProbability(FinishType type, int rating, double contest, double distanceFt) {
  const double skill = InvLerp(40., 99., rating);
  if (type == FinishType::Dunk) {
    const double base = Lerp(0.82, 0.98, skill);
    return Clamp(base - contest * Lerp(0.45, 0.25, skill), 0.05, 0.98);
  }
  const double base = Lerp(0.55, 0.85, skill) - InvLerp(2., 9., distanceFt) * 0.12;
  return Clamp(base - contest * Lerp(0.5, 0.3, skill), 0.05, 0.98);
}

}  // namespace courtlife
