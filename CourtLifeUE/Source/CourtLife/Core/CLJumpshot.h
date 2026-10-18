#pragma once

#include <array>
#include <string_view>

namespace courtlife {

// Jumpshot creator data. In Unreal each base/release maps to an animation
// asset; these numbers drive timing, the green window and contest math so
// the meter always matches what the player sees.

struct ShotBase {
  std::string_view id, label;
  double setPoint, dip, jump, legKick, flare, releaseT, drift, hitch;
};

struct ShotRelease {
  std::string_view id, label;
  double extension, snap, follow, height, tempo, guideOff;
};

constexpr int kShotBaseCount = 8;
constexpr int kShotReleaseCount = 7;
const std::array<ShotBase, kShotBaseCount>& ShotBases();
const std::array<ShotRelease, kShotReleaseCount>& ShotReleases();

struct JumpshotSettings {
  int base = 0;      // index into ShotBases()
  int release1 = 1;  // index into ShotReleases()
  int release2 = 0;
  int blend = 30;    // 0 = all release1, 100 = all release2
  int speed = 3;     // 1..5
};

JumpshotSettings NormalizeJumpshot(JumpshotSettings js);
int FindShotBase(std::string_view id);     // -1 if unknown
int FindShotRelease(std::string_view id);  // -1 if unknown

struct ShotContext {
  int threePoint = 75;
  int vertical = 70;
  int heightIn = 78;
};

struct ShotProfile {
  JumpshotSettings settings;
  float durationMs = 0;
  float releaseT = 0;        // normalized release point in the animation
  float releaseTimeMs = 0;   // when to let go for a perfect release
  float greenWindowMs = 0;
  float jumpFt = 0;
  float releaseHeightFt = 0;
  float contestResist = 0;   // 0..1
  float rhythm = 1;          // 1 = releases share a tempo
  float playRate = 1;        // animation play rate to apply in engine
  float releaseBlend = 0;    // 0..1 upper-body blend between release anims
};

ShotProfile ComputeShotProfile(const JumpshotSettings& js, const ShotContext& ctx);

}  // namespace courtlife
