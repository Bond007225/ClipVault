#include "CLDribble.h"

#include <algorithm>
#include <cmath>
#include <cstdio>

namespace courtlife {

// Must stay in sync with courtlife/src/core/dribble.js.
const std::array<DribbleMove, kDribbleMoveCount>& DribbleMoves() {
  static const std::array<DribbleMove, kDribbleMoveCount> kMoves = {{
      {"crossover", "Crossover", 380, 25, true, {-0.8f, 0.4f}, 0.35f, 0.25f, 0, false},
      {"killCross", "Kill Cross", 300, 75, true, {-1.2f, 0.6f}, 0.55f, 0.45f, 0, false},
      {"betweenLegs", "Between the Legs", 420, 45, true, {0.f, -0.3f}, 0.3f, 0.2f, 0, false},
      {"behindBack", "Behind the Back", 460, 55, true, {-0.6f, 0.3f}, 0.4f, 0.15f, 0, false},
      {"hesitation", "Hesitation", 520, 35, false, {0.f, 1.6f}, 0.45f, -0.15f, 0.25f, false},
      {"inAndOut", "In & Out", 400, 40, false, {0.6f, 0.5f}, 0.35f, 0.3f, 0, false},
      {"spin", "Spin Move", 560, 50, true, {-1.4f, 1.2f}, 0.45f, 0.1f, 0, true},
      {"stepBack", "Step Back", 480, 45, false, {0.f, -2.6f}, 0.5f, -0.3f, 0, false},
      {"snatchBack", "Snatch Back", 440, 80, false, {0.f, -2.0f}, 0.6f, -0.35f, 0, false},
      {"pound", "Pound Dribble", 260, 25, false, {0.f, 0.f}, 0.05f, 0.1f, 0, false},
  }};
  return kMoves;
}

int FindDribbleMove(std::string_view id) {
  const auto& m = DribbleMoves();
  for (int i = 0; i < kDribbleMoveCount; ++i)
    if (m[i].id == id) return i;
  return -1;
}

namespace {
float SideX(Hand h) { return h == Hand::Right ? -1.f : 1.f; }
Hand Other(Hand h) { return h == Hand::Right ? Hand::Left : Hand::Right; }
bool ValidMove(int m) { return m >= 0 && m < kDribbleMoveCount; }
}  // namespace

float MaxStepSpeed(int ballHandle) { return Lerp(1.f, kMaxStepSpeed, InvLerp(60.f, 99.f, static_cast<float>(ballHandle))); }

std::vector<std::string> ValidateCombo(const DribbleCombo& combo, int ballHandle) {
  std::vector<std::string> errors;
  const float cap = MaxStepSpeed(ballHandle);
  char buf[160];
  for (size_t i = 0; i < combo.steps.size(); ++i) {
    const ComboStep& s = combo.steps[i];
    if (!ValidMove(s.move)) {
      std::snprintf(buf, sizeof buf, "Step %zu: unknown move", i + 1);
      errors.emplace_back(buf);
      continue;
    }
    const DribbleMove& m = DribbleMoves()[s.move];
    if (ballHandle < m.minHandle) {
      std::snprintf(buf, sizeof buf, "Step %zu: %.*s needs %d Ball Handle", i + 1, static_cast<int>(m.label.size()),
                    m.label.data(), m.minHandle);
      errors.emplace_back(buf);
    }
    if (s.speed > cap + 1e-6f) {
      std::snprintf(buf, sizeof buf, "Step %zu: max speed is %.2fx at your Ball Handle", i + 1, cap);
      errors.emplace_back(buf);
    }
  }
  if (combo.steps.size() > static_cast<size_t>(kMaxComboSteps)) errors.emplace_back("Too many steps");
  return errors;
}

ComboTimeline BuildComboTimeline(const DribbleCombo& combo, int ballHandle, Hand startHand) {
  ComboTimeline tl;
  const float cap = MaxStepSpeed(ballHandle);
  Hand hand = startHand;
  float time = 0;
  float effectiveness = 0;
  const size_t n = std::min(combo.steps.size(), static_cast<size_t>(kMaxComboSteps));
  for (size_t i = 0; i < n; ++i) {
    const ComboStep& step = combo.steps[i];
    if (!ValidMove(step.move)) continue;
    const DribbleMove& m = DribbleMoves()[step.move];
    if (ballHandle < m.minHandle) continue;
    const float speed = Clamp(step.speed, kMinStepSpeed, cap);
    const float duration = m.durationMs / speed;
    const float side = SideX(hand);
    tl.segments.push_back({step.move, time, time + duration, speed, hand, tl.offset});
    tl.offset.x += m.burst.x * side;
    tl.offset.z += m.burst.z;
    time += duration;
    effectiveness += m.effectiveness * speed * (1.f / (1.f + tl.segments.size() * 0.35f));
    if (m.switchesHand) hand = Other(hand);
  }
  tl.totalMs = time;
  tl.endHand = hand;
  tl.effectiveness = Clamp(effectiveness, 0.f, 1.f);
  return tl;
}

std::optional<ComboSample> SampleCombo(const ComboTimeline& tl, float tMs) {
  if (tl.segments.empty()) return std::nullopt;
  const ComboSegment* seg = &tl.segments.back();
  for (const ComboSegment& s : tl.segments) {
    if (tMs < s.endMs) {
      seg = &s;
      break;
    }
  }
  const DribbleMove& m = DribbleMoves()[seg->move];
  const float local = Clamp((tMs - seg->startMs) / (seg->endMs - seg->startMs), 0.f, 1.f);
  const float side = SideX(seg->hand);
  const float burstK = std::sin(local * kPi * 0.5f);
  ComboSample out;
  out.move = seg->move;
  out.hand = (m.switchesHand && local > 0.5f) ? Other(seg->hand) : seg->hand;
  out.offset = {seg->origin.x + m.burst.x * side * burstK, seg->origin.z + m.burst.z * burstK};
  out.lean = m.lean * std::sin(local * kPi);
  out.rise = m.rise * std::sin(local * kPi);
  out.yaw = m.spin ? -side * local * kPi * 2.f : 0.f;
  out.done = tMs >= tl.totalMs;
  return out;
}

}  // namespace courtlife
