# Building the CourtLife Team

This is the hiring plan for the vertical slice: one park court, the MyPlayer creator, and 1-on-1 with real mocap and MetaHuman players. Job posts are in `roles/`, and the first-week guide for new hires is in `ONBOARDING.md`. A shareable careers page with the same roles exists as a claude.ai artifact; link it from your job posts once placeholders are filled.

Fill in every `[BRACKETED]` placeholder (studio name, contact, pay) before posting anything.

## Team for the vertical slice

| Role | Headcount | Hire in | Job post |
|---|---|---|---|
| Lead Gameplay Programmer (Unreal C++) | 1 | **Wave 1** | [roles/gameplay-programmer.md](roles/gameplay-programmer.md) |
| Technical Artist | 1 | **Wave 1** | [roles/technical-artist.md](roles/technical-artist.md) |
| Character Artist (MetaHuman, clothing, hair) | 1, then 2–3 | **Wave 1** | [roles/character-artist.md](roles/character-artist.md) |
| Animator (mocap and gameplay animation) | 1, then 2–3 | **Wave 1** | [roles/animator.md](roles/animator.md) |
| Gameplay Programmer | 2–3 more | Wave 2 | [roles/gameplay-programmer.md](roles/gameplay-programmer.md) |
| Environment Artist (courts and arenas) | 1–2 | Wave 2 | [roles/environment-artist.md](roles/environment-artist.md) |

**Why this order:**
- **Wave 1 (4 people)** gets the Unreal project compiling and puts one real player on screen with one real jumpshot and one dribble move. That is the smallest version that proves the game looks current-gen.
- The **programmer** fixes the first compile and owns the gameplay code that already exists.
- The **tech artist** sets up the material and rig standards everyone else's work plugs into (see `ONBOARDING.md`). Hiring them early prevents rework.
- The **character artist and animator** produce the first player and the first moves.
- **Wave 2** starts once that works: more programmers for 3v3, passing and layups, and environment artists to build a court good enough to show publishers.

## How to pay people (pick one per person)

| Model | Good for | Risks |
|---|---|---|
| **Paid contract** (hourly or per milestone) | Fastest way to get experienced people. Best for the tech artist and for test tasks. | Needs cash up front. |
| **Revenue share** (a % of game revenue, vested by milestones) | Unfunded passion projects. | Experienced people rarely accept it alone. Turnover is high. Use written agreements. |
| **Equity** in a company you form | Long-term core team (leads). | You need a registered company first. Get a lawyer. |
| **Hybrid** (reduced rate plus rev share or equity) | The usual indie compromise. | Needs the most paperwork. |

**Recommendation:** pay for every test task, even a small fixed fee, so good people take you seriously. Then offer Wave 1 a hybrid deal. Many job boards (for example r/gameDevClassifieds and Work With Indies) require you to state pay or the rev-share terms in the post.

## Where to post

- **Everyone:** LinkedIn, Hitmarker, Work With Indies, r/gameDevClassifieds (follow its posting rules), and the Unreal Slackers Discord jobs channels.
- **Artists and tech artists:** ArtStation Jobs, Polycount forums, 80 Level. Search ArtStation for "MetaHuman", "basketball" and "sports" portfolios and message artists directly.
- **Animators:** the Animation Mentor and iAnimate communities, and LinkedIn searches for "mocap animator" and "sports animation".
- **Programmers:** the Unreal Engine forums, the Unreal Slackers `#looking-for-work` channel, and GitHub (people who contribute to Unreal plugins).
- **The community angle:** post a short clip of the web prototype on X/TikTok/YouTube with the caption "We're building the MyPlayer game the 2K community actually wants — hiring." 2K players who are also developers are your best recruits.

## Hiring process (keep it short and respectful)

1. **Portfolio screen.** You need to see shipped work or a reel. Ignore résumé polish.
2. **30-minute call** covering their best work, interest in basketball games, availability and pay expectations.
3. **Paid test task** (in each job post). It is scoped to 4–8 hours and uses this project's real conventions, so the work is reusable if they're hired.
4. **Review call.** They walk you through the test, you give feedback and see how they take it.
5. **Offer in writing.**

## Paperwork before anyone starts

- [ ] **Contractor or employment agreement** with an **IP assignment** clause, so all work belongs to the studio. This is non-negotiable; a game you can't prove you own can't be published.
- [ ] An **NDA**, if you want the project kept quiet.
- [ ] **Rev-share or equity terms in writing**, with a vesting schedule and what happens if someone leaves.
- [ ] Have a games/entertainment lawyer review the templates once. It costs far less than an ownership dispute later.
- [ ] A registered company (LLC or equivalent) before taking money or signing platform agreements.

## Tools the team needs

| Need | Suggestion |
|---|---|
| Source control for Unreal (large binary assets) | Perforce (Helix Core, free for small teams) or Git with LFS. Plain GitHub alone won't handle art. |
| Tasks | Jira, Linear, HacknPlan or Trello |
| Chat and reviews | Discord or Slack |
| Builds | One shared Windows machine or cloud VM with Unreal for nightly builds |
| Hardware per person | RTX 3070+ GPU, 64 GB RAM, fast SSD |
| Software | Unreal Engine (free), MetaHuman (with Unreal), Maya or Blender, Substance (subscription), Marvelous Designer (subscription), mocap hardware or service when the animation work starts |
