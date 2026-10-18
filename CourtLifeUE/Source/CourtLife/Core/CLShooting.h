#pragma once

#include "CLAttributes.h"
#include "CLMath.h"
#include "CLJumpshot.h"

namespace courtlife {

// Court coordinates in feet: rim centre is the origin of the floor plane and
// the court runs toward +z. In Unreal: 1 ft = 30.48 uu.
constexpr float kRimHeightFt = 10.f;
constexpr float kRimRadiusFt = 0.75f;
constexpr float kThreePtRadiusFt = 23.75f;
constexpr float kCornerThreeXFt = 22.f;
constexpr float kBaselineZFt = -5.25f;

enum class ReleaseGrade { Green, SlightlyEarly, SlightlyLate, Early, Late };

struct ReleaseResult {
  ReleaseGrade grade;
  float deltaMs;
};

bool IsThree(Vec2 spot);
ReleaseResult GradeRelease(const ShotProfile& profile, float heldMs);
/** 0 (wide open) .. 1 (smothered). Pass a negative distance for "no defender". */
float ContestLevel(float defenderDistFt, int defenderHeightIn, float shooterResist);
float MakeProbability(ReleaseGrade grade, int rating, float distanceFt, float contest);
int ShotRating(const Attributes& a, float distanceFt, bool three);

}  // namespace courtlife
