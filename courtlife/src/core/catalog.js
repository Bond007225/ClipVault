// Every customization option in the game lives here so UI, renderer and
// validation all read from one source of truth.

export const POSITIONS = ['PG', 'SG', 'SF', 'PF', 'C'];

export const SKIN_TONES = [
  '#f6d7c3', '#eac0a2', '#d9a37f', '#c68863', '#a86b47',
  '#8d5524', '#71401f', '#5a3218', '#432412', '#2e180c',
];

export const HAIR_STYLES = {
  bald: 'Bald',
  buzz: 'Buzz Cut',
  fade: 'Taper Fade',
  waves: '360 Waves',
  hightop: 'High Top',
  afro: 'Afro',
  twists: 'Twists',
  braids: 'Cornrows',
  dreads: 'Dreads',
  mohawk: 'Mohawk',
  manbun: 'Man Bun',
};

export const FACIAL_HAIR = {
  none: 'Clean Shaven',
  stubble: 'Stubble',
  goatee: 'Goatee',
  chinstrap: 'Chin Strap',
  full: 'Full Beard',
  harden: 'Big Beard',
};

export const EYE_COLORS = ['#3b2314', '#6b4423', '#2e5a88', '#4f7a3a', '#7a7a7a', '#a07a2c'];

export const JERSEY_STYLES = { tank: 'Tank Top', tee: 'Shooting Tee', sleeved: 'Sleeved Jersey' };
export const SHORTS_LENGTHS = { short: 'Retro Short', standard: 'Standard', long: 'Below Knee' };
export const SHOE_MODELS = { low: 'Low Top', mid: 'Mid Top', high: 'High Top' };
export const SOCK_LENGTHS = { ankle: 'Ankle', crew: 'Crew', high: 'Knee High' };
export const SLEEVE_SIDES = { none: 'None', left: 'Left', right: 'Right', both: 'Both' };

export const TATTOO_SLOTS = {
  neck: 'Neck',
  leftUpperArm: 'Left Bicep',
  rightUpperArm: 'Right Bicep',
  leftForearm: 'Left Forearm',
  rightForearm: 'Right Forearm',
  leftHand: 'Left Hand',
  rightHand: 'Right Hand',
  leftCalf: 'Left Calf',
  rightCalf: 'Right Calf',
};

export const TATTOO_DESIGNS = {
  tribal: 'Tribal',
  band: 'Barbed Band',
  rose: 'Rose',
  script: 'Custom Script',
  stars: 'Stars',
  crown: 'Crown',
  geometric: 'Geometric Sleeve',
  flames: 'Flames',
  number: 'Number',
  clock: 'Clock',
  praying: 'Cross',
  waves: 'Waves',
};

export const MAX_TATTOOS_PER_SLOT = 3;
export const MAX_SCRIPT_LENGTH = 16;

export const ATTRIBUTES = {
  closeShot: { label: 'Close Shot', group: 'Finishing' },
  drivingLayup: { label: 'Driving Layup', group: 'Finishing' },
  drivingDunk: { label: 'Driving Dunk', group: 'Finishing' },
  midRange: { label: 'Mid-Range Shot', group: 'Shooting' },
  threePoint: { label: 'Three-Point Shot', group: 'Shooting' },
  freeThrow: { label: 'Free Throw', group: 'Shooting' },
  ballHandle: { label: 'Ball Handle', group: 'Playmaking' },
  speedWithBall: { label: 'Speed With Ball', group: 'Playmaking' },
  passAccuracy: { label: 'Pass Accuracy', group: 'Playmaking' },
  perimeterDefense: { label: 'Perimeter Defense', group: 'Defense' },
  steal: { label: 'Steal', group: 'Defense' },
  block: { label: 'Block', group: 'Defense' },
  speed: { label: 'Speed', group: 'Physicals' },
  acceleration: { label: 'Acceleration', group: 'Physicals' },
  vertical: { label: 'Vertical', group: 'Physicals' },
  strength: { label: 'Strength', group: 'Physicals' },
  stamina: { label: 'Stamina', group: 'Physicals' },
};

export const ATTRIBUTE_MIN = 25;
export const ATTRIBUTE_MAX = 99;

// Body limits in inches/pounds.
export const BODY_LIMITS = {
  heightIn: [69, 87], // 5'9" .. 7'3"
  weightLb: [160, 290],
  wingspanDelta: [-2, 8], // wingspan relative to height
  build: [0, 1], // lean .. muscular
};

export const KEY_BINDINGS = ['1', '2', '3', '4', 'Q', 'E', 'R', 'F'];

export const formatHeight = (inches) => `${Math.floor(inches / 12)}'${Math.round(inches % 12)}"`;
