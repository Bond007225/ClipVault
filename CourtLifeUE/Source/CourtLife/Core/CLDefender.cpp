#include "CLDefender.h"

#include <cmath>

namespace courtlife {

// Must stay in sync with courtlife/src/game/defender.js.

Vec2 GuardSpot(Vec2 h, Vec2 rim, float distFt) {
  const float dx = rim.x - h.x, dz = rim.z - h.z;
  float len = std::hypot(dx, dz);
  if (len == 0) len = 1;
  const float d = std::fmin(distFt, len * 0.6);
  return {h.x + dx / len * d, h.z + dz / len * d};
}

void StepDefender(DefenderState& d, Vec2 handler, Vec2 rim, float dt) {
  if (d.stumble > 0) {
    d.stumble = std::fmax(0., d.stumble - dt);
    d.vel.x *= 0.9;
    d.vel.z *= 0.9;
    d.pos.x += d.vel.x * dt;
    d.pos.z += d.vel.z * dt;
    return;
  }
  d.contest = std::fmax(0., d.contest - dt);
  const float react = Lerp(3.5, 9., InvLerp(40., 99., static_cast<float>(d.perimeterDefense)));
  const float k = 1. - std::exp(-react * dt);
  d.seen.x += (handler.x - d.seen.x) * k;
  d.seen.z += (handler.z - d.seen.z) * k;

  const float distToRim = Distance(handler, rim);
  const float cushion = distToRim > 26. ? 6. : Lerp(2.6, 4., InvLerp(4., 24., distToRim));
  const Vec2 spot = GuardSpot(d.seen, rim, cushion);
  const float maxSpeed = Lerp(9., 14., InvLerp(40., 99., static_cast<float>(d.speed)));
  const float accel = Lerp(30., 60., InvLerp(40., 99., static_cast<float>(d.acceleration)));
  const float dx = spot.x - d.pos.x, dz = spot.z - d.pos.z;
  const float dist = std::hypot(dx, dz);
  const float want = std::fmin(maxSpeed, dist * 6.);
  const float tvx = dist > 0.01 ? dx / dist * want : 0.;
  const float tvz = dist > 0.01 ? dz / dist * want : 0.;
  const float dvx = tvx - d.vel.x, dvz = tvz - d.vel.z;
  const float dv = std::hypot(dvx, dvz);
  const float step = std::fmin(dv, accel * dt);
  if (dv > 0) {
    d.vel.x += dvx / dv * step;
    d.vel.z += dvz / dv * step;
  }
  d.pos.x += d.vel.x * dt;
  d.pos.z += d.vel.z * dt;
}

float AnkleBreakCheck(float effectiveness, int ballHandle, int defense, float distanceFt, float roll) {
  if (distanceFt > 7.) return 0;
  const float proximity = InvLerp(7., 2.5, distanceFt);
  const float skill = Lerp(0.6, 1.35, InvLerp(50., 99., static_cast<float>(ballHandle)));
  const float resist = Lerp(0.1, 0.45, InvLerp(40., 99., static_cast<float>(defense)));
  const float chance = Clamp(effectiveness * skill * (0.5 + proximity * 0.5) - resist, 0.02, 0.85);
  return roll < chance ? Lerp(0.9, 1.8, effectiveness) : 0.;
}

bool StartContest(DefenderState& d, Vec2 shooter) {
  const float dist = Distance(d.pos, shooter);
  if (d.stumble > 0 || dist > 8.) return false;
  d.contest = 0.8;
  const float len = dist == 0 ? 1. : dist;
  d.vel = {(shooter.x - d.pos.x) / len * 8., (shooter.z - d.pos.z) / len * 8.};
  return true;
}

}  // namespace courtlife
