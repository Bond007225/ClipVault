# The CourtLife AI Agent Team

CourtLife is built by a team of AI agents, each with one discipline, coordinated by a producer.

## Roster

| Agent | Definition | Owns |
|---|---|---|
| **Producer** | The main Claude Code session | Sprint planning, task assignment, reviewing and integrating work, commits, this document |
| Gameplay Programmer | `.claude/agents/courtlife-gameplay-programmer.md` | `courtlife/src/core`, `courtlife/src/game`, `courtlife/tests`, `CourtLifeUE/Source`, `CourtLifeUE/Tests` |
| Technical Artist | `.claude/agents/courtlife-technical-artist.md` | `CourtLifeUE/Content/Python/` (except `environments/`), `CourtLifeUE/Docs/TechArt/` |
| Character Artist | `.claude/agents/courtlife-character-artist.md` | `CourtLifeUE/SourceArt/Characters/`, `CourtLifeUE/Docs/Art/Characters/` |
| Animator | `.claude/agents/courtlife-animator.md` | `CourtLifeUE/Docs/Animation/`, procedural poses in the web prototype |
| Environment Artist | `.claude/agents/courtlife-environment-artist.md` | `CourtLifeUE/SourceArt/Environments/`, `CourtLifeUE/Content/Python/environments/`, `CourtLifeUE/Docs/Art/Environments/` |

In any Claude Code session in this repo, an agent can be called by name, for example "use the courtlife-animator agent to…".

## How the team works

1. **Sprint planning.** The producer picks a goal and gives each agent one self-contained task with a clear definition of done.
2. **Parallel work.** Agents work at the same time in their own folders. File ownership prevents agents from overwriting each other. Agents never run git.
3. **Contracts are the interface.** Agents coordinate through the content contracts in `ONBOARDING.md` (material parameters, bone names, catalog keys, court units) and through the requests in their reports.
4. **Verification.** Every agent proves its work in this environment: tests, compiles, syntax checks, and for art, viewing the generated images.
5. **Review and integration.** The producer reviews each report, re-runs the checks, fixes cross-agent mismatches and commits.
6. **Next sprint.** Requests between agents (for example animator → programmer) become the next sprint's tasks.

## What the agent team can and can't do

| Can do in this environment | Needs a human, or tools not available here |
|---|---|
| All gameplay code and tests (web prototype and C++ core) | Compiling and running Unreal Engine (needs a Windows PC with a GPU) |
| Unreal C++ and editor Python, written but not run | Testing in Unreal, profiling on consoles |
| Procedural textures: tattoos, court floors, masks | Photoreal MetaHuman faces and bodies, sculpted clothing, groom hair |
| Animation specs, timing tables, procedural motion | Motion capture and polished keyframe animation |
| Docs, plans, pipeline automation | Console dev kits, platform approvals, company registration, legal |

The right-hand column is the part to bring in later, when you have the hardware or funding, using the hiring kit in this folder (`README.md`, `roles/`).

## Sprint log

### Sprint 1: foundations
- **Gameplay Programmer:** finishing system (layups and dunks) in the JS and C++ cores with parity tests, plus web prototype integration.
- **Technical Artist:** Unreal Python project bootstrap (folders, master materials, data assets), tattoo atlas layout, material and budget docs.
- **Character Artist:** production tattoo stencil set (procedural, R = ink / G = accent) with checks and a preview sheet.
- **Environment Artist:** park and gym half-court textures at regulation dimensions, line tests, Unreal blockout script, park court brief.
- **Animator:** naming conventions, mocap shot list, anim blueprint spec, timing reference generated from code.
