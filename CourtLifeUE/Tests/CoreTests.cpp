// Unit + parity tests for the engine-independent gameplay core.
// Build & run: cmake -S . -B build && cmake --build build && ./build/courtlife_core_tests
#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

#include "CLAttributes.h"
#include "CLDefender.h"
#include "CLDribble.h"
#include "CLJumpshot.h"
#include "CLShooting.h"

using namespace courtlife;

namespace {
int g_failures = 0;
int g_checks = 0;
std::string g_test;

void Check(bool ok, const char* expr, const char* file, int line) {
  ++g_checks;
  if (!ok) {
    ++g_failures;
    std::printf("  FAIL [%s] %s:%d  %s\n", g_test.c_str(), file, line, expr);
  }
}
void Near(double a, double b, double tol, const char* expr, const char* file, int line) {
  ++g_checks;
  if (std::fabs(a - b) > tol) {
    ++g_failures;
    std::printf("  FAIL [%s] %s:%d  %s  (%.6f vs %.6f)\n", g_test.c_str(), file, line, expr, a, b);
  }
}
#define CHECK(x) Check((x), #x, __FILE__, __LINE__)
#define NEAR(a, b, tol) Near((a), (b), (tol), #a " ~= " #b, __FILE__, __LINE__)

std::vector<std::pair<const char*, std::function<void()>>>& Registry() {
  static std::vector<std::pair<const char*, std::function<void()>>> r;
  return r;
}
struct Reg {
  Reg(const char* n, std::function<void()> f) { Registry().emplace_back(n, std::move(f)); }
};
#define TEST(name) \
  static void name(); \
  static Reg reg_##name(#name, name); \
  static void name()

#include "Golden.inc"

Body MakeBody(int h, int w, int ws) { return Body{h, w, ws, 0.5f}; }
}  // namespace

// ---------------------------------------------------------------- parity with the web creator
TEST(ShotProfileMatchesWeb) {
  for (const auto& g : kShotGolden) {
    const ShotProfile p = ComputeShotProfile({g.base, g.r1, g.r2, g.blend, g.speed}, {g.three, g.vert, g.height});
    NEAR(p.releaseTimeMs, g.releaseMs, 0.5);
    NEAR(p.greenWindowMs, g.greenMs, 0.5);
    NEAR(p.releaseHeightFt, g.relHeight, 1e-3);
    NEAR(p.contestResist, g.resist, 1e-3);
  }
}

TEST(AttributeCapsMatchWeb) {
  for (const auto& g : kCapsGolden) {
    const Attributes caps = AttributeCaps(MakeBody(g.height, g.weight, g.wingspan));
    for (int i = 0; i < kAttrCount; ++i) CHECK(caps[i] == g.caps[i]);
  }
}

TEST(ComboTimelineMatchesWeb) {
  for (const auto& g : kComboGolden) {
    DribbleCombo c;
    for (int i = 0; i < g.n; ++i) c.steps.push_back({g.moves[i], g.speeds[i]});
    const ComboTimeline tl = BuildComboTimeline(c, g.handle, g.hand == 0 ? Hand::Right : Hand::Left);
    NEAR(tl.totalMs, g.totalMs, 0.05);
    NEAR(tl.effectiveness, g.effectiveness, 1e-3);
    NEAR(tl.offset.x, g.offX, 1e-3);
    NEAR(tl.offset.z, g.offZ, 1e-3);
    CHECK(static_cast<int>(tl.endHand) == g.endHand);
  }
}

TEST(MakeProbabilityMatchesWeb) {
  for (const auto& g : kMakeGolden) {
    const float contest = ContestLevel(g.defDist, g.defHeight, g.resist);
    NEAR(contest, g.contest, 1e-4);
    NEAR(MakeProbability(static_cast<ReleaseGrade>(g.grade), g.rating, g.dist, contest), g.prob, 1e-4);
  }
}

// ---------------------------------------------------------------- attributes
TEST(TallPlayersTradeHandlesForRimProtection) {
  const Attributes guard = AttributeCaps(MakeBody(72, 175, 74));
  const Attributes big = AttributeCaps(MakeBody(85, 260, 90));
  CHECK(Get(guard, Attr::BallHandle) > Get(big, Attr::BallHandle));
  CHECK(Get(big, Attr::Block) > Get(guard, Attr::Block));
}

TEST(LegalizeRespectsCapsAndBudget) {
  const Body b = MakeBody(84, 250, 88);
  Attributes maxed;
  maxed.fill(99);
  const Attributes out = LegalizeAttributes(maxed, b);
  const Attributes caps = AttributeCaps(b);
  for (int i = 0; i < kAttrCount; ++i) CHECK(out[i] <= caps[i]);
  CHECK(PointsUsed(out) <= kAttributeBudget);
}

TEST(SetAttributeHonorsBudget) {
  const Body b = MakeBody(75, 190, 79);
  Attributes a;
  a.fill(68);
  const int v = SetAttribute(a, b, Attr::ThreePoint, 99);
  Attributes after = a;
  Get(after, Attr::ThreePoint) = v;
  CHECK(PointsUsed(after) <= kAttributeBudget);
  CHECK(v >= kAttrMin);
}

TEST(NormalizeBodyClamps) {
  const Body b = NormalizeBody({200, 10, 500, 3.f});
  CHECK(b.heightIn == kHeightMax);
  CHECK(b.weightLb == kWeightMin);
  CHECK(b.wingspanIn == kHeightMax + kWingspanDeltaMax);
  CHECK(b.build == 1.f);
}

// ---------------------------------------------------------------- jumpshot
TEST(FasterShotsReleaseSooner) {
  JumpshotSettings slow, fast;
  slow.speed = 1;
  fast.speed = 5;
  CHECK(ComputeShotProfile(fast, {}).releaseTimeMs < ComputeShotProfile(slow, {}).releaseTimeMs);
}

TEST(TempoClashShrinksGreenWindow) {
  JumpshotSettings pure{0, FindShotRelease("quickFlick"), FindShotRelease("highArc"), 0, 3};
  JumpshotSettings mixed = pure;
  mixed.blend = 50;
  CHECK(ComputeShotProfile(mixed, {}).greenWindowMs < ComputeShotProfile(pure, {}).greenWindowMs);
}

TEST(NormalizeJumpshotFixesGarbage) {
  const JumpshotSettings js = NormalizeJumpshot({99, -4, 99, 400, 0});
  CHECK(js.base == 0 && js.release1 == 1 && js.release2 == 0 && js.blend == 100 && js.speed == 1);
}

// ---------------------------------------------------------------- dribble
TEST(BallHandleGatesMovesAndSpeed) {
  DribbleCombo c{"x", '1', {{FindDribbleMove("crossover"), 1.f}, {FindDribbleMove("snatchBack"), 1.5f}}};
  CHECK(ValidateCombo(c, 60).size() == 2);
  CHECK(ValidateCombo(c, 99).empty());
  const ComboTimeline locked = BuildComboTimeline(c, 60);
  CHECK(locked.segments.size() == 1);
  CHECK(locked.endHand == Hand::Left);
}

TEST(RightHandCrossMovesPlayerLeft) {
  DribbleCombo c{"x", '1', {{FindDribbleMove("crossover"), 1.f}}};
  const ComboTimeline tl = BuildComboTimeline(c, 80, Hand::Right);
  CHECK(tl.offset.x > 0);
  const auto end = SampleCombo(tl, tl.totalMs);
  CHECK(end.has_value() && end->done && end->hand == Hand::Left);
}

TEST(SpinRotatesFullCircle) {
  DribbleCombo c{"x", '1', {{FindDribbleMove("spin"), 1.f}}};
  const ComboTimeline tl = BuildComboTimeline(c, 80, Hand::Right);
  NEAR(std::fabs(SampleCombo(tl, tl.totalMs)->yaw), 2 * kPi, 1e-4);
}

TEST(EmptyComboHasNoSample) { CHECK(!SampleCombo(BuildComboTimeline({}, 99), 0).has_value()); }

// ---------------------------------------------------------------- shooting
TEST(ReleaseGrading) {
  const ShotProfile p = ComputeShotProfile({}, {85, 70, 78});
  CHECK(GradeRelease(p, p.releaseTimeMs).grade == ReleaseGrade::Green);
  CHECK(GradeRelease(p, p.releaseTimeMs - 400).grade == ReleaseGrade::Early);
  CHECK(GradeRelease(p, p.releaseTimeMs + 400).grade == ReleaseGrade::Late);
}

TEST(ThreePointLine) {
  CHECK(IsThree({0, 25}));
  CHECK(!IsThree({0, 15}));
  CHECK(IsThree({22.5f, 0}));
}

// ---------------------------------------------------------------- defender
TEST(DefenderConvergesBetweenHandlerAndRim) {
  DefenderState d;
  d.pos = {10, 30};
  d.perimeterDefense = 80;
  for (int i = 0; i < 300; ++i) StepDefender(d, {0, 25}, {0, 0}, 1.f / 60.f);
  CHECK(std::fabs(d.pos.x) < 0.5f);
  CHECK(d.pos.z < 25 && d.pos.z > 18);
}

TEST(AnkleBreaksNeedProximityAndSkill) {
  CHECK(AnkleBreakCheck(0.6f, 95, 60, 10, 0.3f) == 0);
  CHECK(AnkleBreakCheck(0.6f, 95, 60, 3, 0.3f) > 0);
  CHECK(AnkleBreakCheck(0.6f, 50, 99, 3, 0.3f) == 0);
}

TEST(ContestOnlyWhenCloseAndUpright) {
  DefenderState d;
  d.pos = {0, 20};
  CHECK(StartContest(d, {0, 23}));
  DefenderState down = d;
  down.stumble = 1;
  CHECK(!StartContest(down, {0, 23}));
  CHECK(!StartContest(d, {0, 35}));
}

int main() {
  for (auto& [name, fn] : Registry()) {
    g_test = name;
    const int before = g_failures;
    fn();
    std::printf("%s %s\n", g_failures == before ? "PASS" : "FAIL", name);
  }
  std::printf("\n%zu tests, %d checks, %d failures\n", Registry().size(), g_checks, g_failures);
  return g_failures ? 1 : 0;
}
