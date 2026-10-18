# Animator (Mocap and Gameplay Animation)

## About CourtLife

CourtLife is a basketball game built entirely around **MyPlayer**. You create one player and customize everything: body, face, hair, clothes, tattoos (including your own written text), your **own jumpshot** (a base blended with two releases), and your **own dribble combos** bound to buttons. It is built in **Unreal Engine 5** with MetaHuman, Lumen and Nanite, targeting PC first and then PlayStation and Xbox.

This is not a pitch deck with nothing behind it. There is a playable web prototype, a tested C++ gameplay core, and an Unreal project with the character, shot meter, dribble system, ball, defender AI and customization code already written. We are hiring the first team to make it look and feel like a current-gen game.

**Studio:** [STUDIO NAME] · **Location:** Remote ([TIME ZONES]) · **Contact:** [EMAIL / DISCORD] · **Pay:** [PAY or RATE or REV-SHARE TERMS]

## What you will do

- Plan and run motion-capture sessions with real hoopers, then clean up and polish the data.
- **Jumpshots:** 8 lower-body bases and 7 upper-body releases, captured so any base can blend with any two releases. Each base needs a "Release" notify at the exact release frame, because the shot meter is timed to it.
- **Dribble moves:** crossover, kill cross, between the legs, behind the back, hesitation, in-and-out, spin, step back, snatch back and pound. Each move needs right-hand and left-hand versions with root motion.
- **Locomotion sets** for Motion Matching (with and without the ball), plus defensive slides, contests, stumbles ("ankles broken"), rebounds and celebrations.
- Animate the ball as a `ball_prop` bone in every clip so dribbles look hand-perfect.

## Must have

- Gameplay animation shipped in a game engine, ideally Unreal Engine 5.
- Mocap cleanup experience (MotionBuilder, Maya or Blender).
- An eye for weight and athletic timing.

## Nice to have

- Sports or fighting game animation.
- Motion Matching/PoseSearch, the IK Retargeter, root motion setup.
- You hoop, and you know what a good jumper looks like.

## Paid test task (about 8 hours, [TEST FEE])

1. Animate (or clean up provided mocap for) one **crossover**, right hand to left hand, with root motion and a `ball_prop` bone.
2. Make it loop out of and back into a stationary dribble idle.
3. Show it in Unreal on the UE5 mannequin, and say how you would build the left-hand version.
