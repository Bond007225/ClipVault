#pragma once

#include <array>
#include <string_view>

namespace courtlife {

enum class Attr : int {
  CloseShot, DrivingLayup, DrivingDunk, MidRange, ThreePoint, FreeThrow,
  BallHandle, SpeedWithBall, PassAccuracy, PerimeterDefense, Steal, Block,
  Speed, Acceleration, Vertical, Strength, Stamina,
  Count
};

constexpr int kAttrCount = static_cast<int>(Attr::Count);
constexpr int kAttrMin = 25;
constexpr int kAttrMax = 99;
constexpr int kAttributeBudget = 1150;

enum class Position { PG, SG, SF, PF, C };

using Attributes = std::array<int, kAttrCount>;

struct Body {
  int heightIn = 75;
  int weightLb = 190;
  int wingspanIn = 79;
  float build = 0.5f;  // 0 lean .. 1 muscular
};

constexpr int kHeightMin = 69, kHeightMax = 87;
constexpr int kWeightMin = 160, kWeightMax = 290;
constexpr int kWingspanDeltaMin = -2, kWingspanDeltaMax = 8;

inline int Get(const Attributes& a, Attr k) { return a[static_cast<int>(k)]; }
inline int& Get(Attributes& a, Attr k) { return a[static_cast<int>(k)]; }

std::string_view AttrName(Attr k);

/** Per-attribute cap from the player's frame: tradeoffs, not pay-to-win. */
Attributes AttributeCaps(const Body& body);
int PointsUsed(const Attributes& a);
/** Clamp to caps, then shave the highest ratings until within budget. */
Attributes LegalizeAttributes(const Attributes& a, const Body& body);
/** The value actually allowed when trying to set one attribute. */
int SetAttribute(const Attributes& a, const Body& body, Attr key, int value);
int OverallRating(const Attributes& a, Position pos);
Body NormalizeBody(Body body);

}  // namespace courtlife
