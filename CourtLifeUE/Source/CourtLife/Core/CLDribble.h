#pragma once

#include <array>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "CLMath.h"

namespace courtlife {

// Dribble creator: chain moves into combos with per-step speed. In Unreal
// each move is a montage; the timeline below decides durations (montage play
// rate), hand switches, displacement and how hard the combo is to guard.

enum class Hand { Right, Left };

struct DribbleMove {
  std::string_view id, label;
  float durationMs;
  int minHandle;
  bool switchesHand;
  Vec2 burst;  // ft, x relative to the starting hand (negative = toward the other side)
  float effectiveness;
  float lean;
  float rise;
  bool spin;
};

constexpr int kDribbleMoveCount = 10;
constexpr int kMaxComboSteps = 6;
constexpr int kMaxCombos = 8;
constexpr float kMinStepSpeed = 0.6f;
constexpr float kMaxStepSpeed = 1.5f;

const std::array<DribbleMove, kDribbleMoveCount>& DribbleMoves();
int FindDribbleMove(std::string_view id);  // -1 if unknown

struct ComboStep {
  int move = 0;
  float speed = 1.f;
};

struct DribbleCombo {
  std::string name;
  char key = '1';
  std::vector<ComboStep> steps;
};

/** Fastest step speed a handler can pull off: 60 handle = 1.0x, 99 = 1.5x. */
float MaxStepSpeed(int ballHandle);

/** Human-readable problems (locked moves, too fast). Empty when valid. */
std::vector<std::string> ValidateCombo(const DribbleCombo& combo, int ballHandle);

struct ComboSegment {
  int move;
  float startMs, endMs;
  float speed;  // == montage play rate
  Hand hand;
  Vec2 origin;
};

struct ComboTimeline {
  std::vector<ComboSegment> segments;
  float totalMs = 0;
  Hand endHand = Hand::Right;
  Vec2 offset;
  float effectiveness = 0;  // 0..1 "ankle breaker" rating
};

/** Locked moves are dropped and speeds clamped so builds can't cheat. */
ComboTimeline BuildComboTimeline(const DribbleCombo& combo, int ballHandle, Hand startHand = Hand::Right);

struct ComboSample {
  int move;
  Hand hand;
  Vec2 offset;  // local displacement from the combo start (player faces +z, right side is -x)
  float lean, rise, yaw;
  bool done;
};

std::optional<ComboSample> SampleCombo(const ComboTimeline& tl, float tMs);

}  // namespace courtlife
