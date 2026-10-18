#include "CLJumpshot.h"

#include <algorithm>
#include <cmath>

#include "CLMath.h"

namespace courtlife {

// Must stay in sync with courtlife/src/core/jumpshot.js.
const std::array<ShotBase, kShotBaseCount>& ShotBases() {
  static const std::array<ShotBase, kShotBaseCount> kBases = {{
      {"classic", "Classic", 0.7, 0.35, 1.0, 0., 0.1, 0.66, 0., 0.},
      {"quickSet", "Quick Set", 0.3, 0.22, 0.8, 0., 0.05, 0.58, 0., 0.},
      {"highSet", "High Set", 1.0, 0.4, 1.05, 0., 0.05, 0.7, 0., 0.},
      {"sideSet", "Side Set", 0.6, 0.3, 0.95, 0.1, 0.55, 0.64, 0., 0.},
      {"oneMotion", "One Motion", 0.55, 0.5, 0.9, 0., 0.15, 0.62, 0.1, 0.},
      {"setShot", "Set Shot", 0.5, 0.3, 0.15, 0., 0.1, 0.6, 0., 0.},
      {"legKick", "Leg Kick", 0.75, 0.35, 1.0, 0.9, 0.15, 0.68, 0.3, 0.},
      {"hitch", "Hitch", 0.85, 0.35, 1.0, 0.2, 0.1, 0.74, 0., 0.12},
  }};
  return kBases;
}

const std::array<ShotRelease, kShotReleaseCount>& ShotReleases() {
  static const std::array<ShotRelease, kShotReleaseCount> kReleases = {{
      {"quickFlick", "Quick Flick", 0.8, 1.0, 0.3, 0.45, 1.15, 0.3},
      {"highArc", "High Arc", 1.0, 0.8, 0.85, 1.0, 0.95, 0.4},
      {"push", "Push", 0.7, 0.4, 0.4, 0.3, 1.0, 0.2},
      {"smoothHold", "Smooth Hold", 1.0, 0.9, 1.0, 0.8, 1.0, 0.5},
      {"guideFlare", "Guide Hand Flare", 0.9, 0.9, 0.6, 0.7, 1.02, 1.0},
      {"slingshot", "Slingshot", 0.85, 0.7, 0.5, 0.55, 1.1, 0.35},
      {"wristy", "Wristy", 0.75, 1.0, 0.7, 0.6, 1.08, 0.25},
  }};
  return kReleases;
}

int FindShotBase(std::string_view id) {
  const auto& b = ShotBases();
  for (int i = 0; i < kShotBaseCount; ++i)
    if (b[i].id == id) return i;
  return -1;
}

int FindShotRelease(std::string_view id) {
  const auto& r = ShotReleases();
  for (int i = 0; i < kShotReleaseCount; ++i)
    if (r[i].id == id) return i;
  return -1;
}

JumpshotSettings NormalizeJumpshot(JumpshotSettings js) {
  const JumpshotSettings def;
  if (js.base < 0 || js.base >= kShotBaseCount) js.base = def.base;
  if (js.release1 < 0 || js.release1 >= kShotReleaseCount) js.release1 = def.release1;
  if (js.release2 < 0 || js.release2 >= kShotReleaseCount) js.release2 = def.release2;
  js.blend = std::clamp(js.blend, 0, 100);
  js.speed = std::clamp(js.speed, 1, 5);
  return js;
}

ShotProfile ComputeShotProfile(const JumpshotSettings& in, const ShotContext& ctx) {
  const JumpshotSettings js = NormalizeJumpshot(in);
  const ShotBase& base = ShotBases()[js.base];
  const ShotRelease& r1 = ShotReleases()[js.release1];
  const ShotRelease& r2 = ShotReleases()[js.release2];
  const double t = js.blend / 100.0;
  const double tempo = Lerp(r1.tempo, r2.tempo, t);
  const double relHeight = Lerp(r1.height, r2.height, t);
  const double relExtension = Lerp(r1.extension, r2.extension, t);

  ShotProfile p;
  p.settings = js;
  p.releaseBlend = t;
  const double speedMult = Lerp(0.8, 1.25, (js.speed - 1) / 4.) * tempo;
  p.playRate = speedMult;
  const double durationMs = std::round(1050.0 / speedMult);
  p.durationMs = static_cast<float>(durationMs);
  const double releaseT = Clamp(base.releaseT + base.hitch * 0.5, 0.5, 0.85);
  p.releaseT = static_cast<float>(releaseT);
  p.releaseTimeMs = static_cast<float>(std::round(durationMs * releaseT));

  const double tempoClash = std::fabs(r1.tempo - r2.tempo);
  const double blendMix = std::min(js.blend, 100 - js.blend) / 50.;
  p.rhythm = 1. - tempoClash * blendMix * 1.5;

  const double ratingWindow = Lerp(18., 52., InvLerp(50., 99., static_cast<float>(ctx.threePoint)));
  const double speedAdjust = (3 - js.speed) * 2.5;
  p.greenWindowMs = std::round(Clamp((ratingWindow + speedAdjust) * p.rhythm, 10., 70.));

  p.jumpFt = base.jump * Lerp(0.6, 1.6, InvLerp(25., 99., static_cast<float>(ctx.vertical)));
  p.releaseHeightFt = (ctx.heightIn / 12.) * 1.18 + base.setPoint * 0.35 + relHeight * 0.45 +
                      relExtension * 0.2 + p.jumpFt;
  p.contestResist = Clamp(InvLerp(7.5, 12., p.releaseHeightFt) * 0.6 +
                              InvLerp(500., 320., p.releaseTimeMs) * 0.4,
                          0., 1.);
  return p;
}

}  // namespace courtlife
