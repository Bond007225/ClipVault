#pragma once

#include "CLAttributes.h"

namespace courtlife {

// Finishing at the rim: layups and dunks. Pressing shoot close to the basket
// picks a finish instead of a jumper. Mirrors courtlife/src/core/finishing.js.

enum class FinishType { None, Layup, Dunk };

constexpr double kFinishMaxRangeFt = 9.0;  // past this every shot is a jumper
constexpr double kRimHeightIn = 120.0;
constexpr double kDunkClearanceIn = 6.0;   // the hand has to get this far above the rim
constexpr int kMinDunkRating = 55;
constexpr double kBlockContest = 0.55;     // a missed finish this contested reads as a block

struct FinishInput {
  double distanceFt = 0.0;
  double speedFtPerSec = 0.0;
  int closeShot = 70;
  int drivingLayup = 75;
  int drivingDunk = 60;
  int vertical = 70;
  int heightIn = 78;
};

/** How high (inches) the hand gets at the peak of a running jump. */
double DunkReachIn(int heightIn, int vertical, double speedFtPerSec);
double LayupRangeFt(double speedFtPerSec);
double DunkRangeFt(int drivingDunk, double speedFtPerSec);

/** FinishType::None = too far, take a jumper. */
FinishType ChooseFinish(const FinishInput& in);
FinishType ChooseFinish(double distanceFt, double speedFtPerSec, const Attributes& a, int heightIn);

/** Which rating governs a finish. */
int FinishRating(const Attributes& a, FinishType type, double distanceFt);

struct FinishContext {
  int rating = 75;
  int vertical = 70;
  int heightIn = 78;
  double distanceFt = 4.0;
};

/** Timing data shaped like ShotProfile so a timed finish meter can reuse it. */
struct FinishProfile {
  FinishType type = FinishType::Layup;
  double gatherMs = 0;
  double durationMs = 0;
  double releaseTimeMs = 0;  // ball leaves the hand / hits the rim
  double releaseT = 0;       // normalized release point in the animation
  double greenWindowMs = 0;
  double jumpFt = 0;
  double releaseHeightFt = 0;
  double contestResist = 0;  // 0..1
};

FinishProfile ComputeFinishProfile(FinishType type, const FinishContext& ctx);
double FinishMakeProbability(FinishType type, int rating, double contest, double distanceFt);
inline bool IsBlocked(bool made, double contest) { return !made && contest >= kBlockContest; }

}  // namespace courtlife
