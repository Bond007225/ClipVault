#pragma once

#include "CLAttributes.h"
#include "CLMath.h"

namespace courtlife {

// On-ball defender brain, shared by the AI controller in Unreal.

struct DefenderState {
  Vec2 pos{0.f, 14.f};
  Vec2 vel;
  Vec2 seen{0.f, 20.f};  // lagged read of the ball handler
  double stumble = 0;    // seconds left recovering from a broken ankle
  double contest = 0;    // seconds left in a contest jump
  int perimeterDefense = 75;
  int speed = 75;
  int acceleration = 75;
};

Vec2 GuardSpot(Vec2 handler, Vec2 rim, float distFt);
void StepDefender(DefenderState& d, Vec2 handler, Vec2 rim, float dt);
/** Stumble duration in seconds (0 = stayed in front). `roll` in [0,1). */
float AnkleBreakCheck(float effectiveness, int ballHandle, int defense, float distanceFt, float roll);
bool StartContest(DefenderState& d, Vec2 shooter);

}  // namespace courtlife
