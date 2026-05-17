const DEFAULT_AMBIENT_AUDIO_BASE = 'https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-audio';
const MAX_CUSTOM_AMBIENT_TRACKS = 5;
const AMBIENT_AUDIO_MODES = Object.freeze({
  VIDEO: 'video',
  CUSTOM: 'custom',
});

const AMBIENT_TRACKS = Object.freeze({
  ocean: {
    id: 'ocean',
    label: '海浪',
    file: 'ocean-soft-waves.mp3',
    durationMs: 180114,
    volume: 0.5,
  },
  oceanGulls: {
    id: 'oceanGulls',
    label: '海鸥海浪',
    file: 'gentle-ocean-waves-birdsong-and-gull.mp3',
    durationMs: 115152,
    volume: 0.66,
  },
  underwater: {
    id: 'underwater',
    label: '水下',
    file: 'underwater-ambience.mp3',
    durationMs: 46920,
    volume: 0.28,
  },
  forest: {
    id: 'forest',
    label: '森林',
    file: 'forest-ambience.mp3',
    durationMs: 212976,
    volume: 0.54,
  },
  forestWindBirds: {
    id: 'forestWindBirds',
    label: '山林风鸟',
    file: 'forest-wind-and-birds.mp3',
    durationMs: 196104,
    volume: 0.54,
  },
  river: {
    id: 'river',
    label: '溪流',
    file: 'river-stream.mp3',
    durationMs: 120111,
    volume: 0.52,
  },
  waterfall: {
    id: 'waterfall',
    label: '瀑布',
    file: 'waterfall.mp3',
    durationMs: 82155,
    volume: 0.44,
  },
  birds: {
    id: 'birds',
    label: '鸟鸣',
    file: 'birds.mp3',
    durationMs: 180000,
    volume: 0.62,
  },
  wind: {
    id: 'wind',
    label: '风声',
    file: 'wind-in-trees.mp3',
    durationMs: 147931,
    volume: 0.54,
  },
  sky: {
    id: 'sky',
    label: '天空',
    file: 'mountain-sky-ambience.mp3',
    durationMs: 48024,
    volume: 0.52,
  },
  lightRain: {
    id: 'lightRain',
    label: '雨声',
    file: 'light-rain.mp3',
    durationMs: 104359,
    volume: 0.34,
  },
  fire: {
    id: 'fire',
    label: '炉火',
    file: 'fire-crackling.mp3',
    durationMs: 79536,
    volume: 0.3,
  },
  tractor: {
    id: 'tractor',
    label: '收割机',
    file: 'tractor-harvesting.mp3',
    durationMs: 249731,
    volume: 0.36,
  },
});

const CUSTOM_AMBIENT_TRACK_IDS = Object.freeze([
  'wind',
  'waterfall',
  'sky',
  'fire',
  'lightRain',
  'river',
  'birds',
  'forestWindBirds',
  'forest',
  'ocean',
  'oceanGulls',
  'underwater',
]);

const CUSTOM_AMBIENT_LABELS = Object.freeze({
  wind: '林中风',
  waterfall: '瀑布',
  sky: '高空',
  fire: '火',
  lightRain: '小雨',
  river: '溪流',
  birds: '鸟叫',
  forestWindBirds: '山中鸟叫',
  forest: '森林',
  ocean: '海浪',
  oceanGulls: '海鸥海浪',
  underwater: '水下',
});

const AMBIENT_VIDEO_OVERRIDES = Object.freeze({
  'mixkit-sunset-reveal-over-scenic-lagoon-101208': 'sky',
  'mixkit-aerial-view-of-a-city-during-the-night-4308': 'sky',
  'mixkit-city-of-tokyo-at-night-4383': 'sky',
  'pixabay-347325': 'sky',
  'pixabay-323513': 'sky',
  'pixabay-328740': 'sky',
  'pixabay-181376': 'birds',
  'pixabay-325502': 'sky',
  'pixabay-305657': 'forestWindBirds',
  'pixabay-108366': 'underwater',
  'pixabay-287510': 'river',
  'pixabay-307864': 'sky',
  'pixabay-276047': 'sky',
  'pixabay-283431': 'sky',
  'pixabay-266987': [
    { trackId: 'sky', volume: 0.52 },
    { trackId: 'birds', volume: 0.16 },
  ],
  'pixabay-240841': [
    { trackId: 'sky', volume: 1 },
    { trackId: 'birds', volume: 0.08 },
  ],
  'pixabay-265501': 'forestWindBirds',
  'pixabay-232561': 'tractor',
  'pixabay-191159': 'wind',
  'pixabay-268528': null,
  'pixabay-260895': 'sky',
  'pixabay-260397': 'wind',
  'pixabay-253436': 'sky',
  'pixabay-271161': 'waterfall',
  'pixabay-204006': 'sky',
  'pixabay-221180': 'sky',
  'pixabay-228847': 'waterfall',
  'pixabay-28707': 'waterfall',
  'pixabay-175876': [
    { trackId: 'sky', volume: 0.24 },
    { trackId: 'wind', volume: 0.12 },
  ],
  'pixabay-111179': 'sky',
  'pixabay-140111': 'oceanGulls',
  'pixabay-159703': 'river',
});

const AMBIENT_RULES = Object.freeze([
  {
    trackId: 'waterfall',
    any: ['waterfall', 'waterfalls', 'niagara falls', 'water falls', 'falls', 'whitewater'],
  },
  {
    trackId: 'forestWindBirds',
    any: ['alps', 'swiss alps'],
  },
  {
    trackId: 'lightRain',
    any: ['rain', 'water drops', 'wet', 'drops', 'glass', 'window'],
  },
  {
    trackId: 'fire',
    any: ['campfire', 'fireplace', 'flames'],
    none: ['fireworks', 'lava', 'volcano', 'eruption'],
  },
  {
    trackId: 'underwater',
    any: [
      'underwater',
      'aquarium',
      'jellyfish',
      'fish',
      'fishes',
      'clownfish',
      'clown fish',
      'catfish',
      'reef',
      'reef fish',
      'sea anemone',
      'anemone',
      'turtle',
      'diving',
      'scuba',
      'marine',
      'marine life',
      'marine worms',
      'sea creatures',
      'pool',
    ],
    none: ['rainforest'],
  },
  {
    trackId: 'birds',
    any: ['bird', 'birds', 'baby bird', 'duck', 'gull', 'seagulls', 'kingfisher', 'shrike'],
  },
  {
    trackId: 'river',
    any: ['river', 'stream'],
  },
  {
    trackId: 'forest',
    any: [
      'forest',
      'woods',
      'moss',
      'trees',
      'stream',
      'grass',
      'plants',
      'plant',
      'garden',
      'flowers',
      'cherry blossoms',
      'sakura',
      'plum',
      'lizard',
      'dew',
    ],
    none: ['underwater', 'aquarium', 'fish', 'jellyfish'],
  },
  {
    trackId: 'ocean',
    any: [
      'ocean',
      'sea',
      'beach',
      'coast',
      'coastline',
      'lagoon',
      'shoreline',
      'waves',
      'wave',
      'surf',
      'seascape',
      'sand',
      'harbor',
      'marina',
      'sailboats',
    ],
    none: ['underwater', 'aquarium', 'fish', 'jellyfish', 'turtle', 'sea of fog', 'fireworks'],
  },
]);

function normalizeBase(base) {
  return String(base || '').trim().replace(/\/$/, '');
}

function collectTerms(video) {
  if (!video) return [];
  return [
    video.category,
    video.timeOfDay,
    video.locationName,
    video.name,
    video.originalName,
    ...(video.subcategories || []),
    ...(video.tags || []),
  ]
    .filter(Boolean)
    .map((item) => String(item).trim().toLowerCase())
    .filter(Boolean);
}

function hasAnyTerm(terms, matches) {
  return matches.some((match) => terms.includes(match));
}

function matchesRule(terms, rule) {
  if (rule.none && hasAnyTerm(terms, rule.none)) return false;
  return hasAnyTerm(terms, rule.any || []);
}

function hydrateTrack(spec, base) {
  const trackId = typeof spec === 'string' ? spec : spec && spec.trackId;
  const track = AMBIENT_TRACKS[trackId];
  if (!track) return null;

  const volume = spec && typeof spec === 'object' && spec.volume != null
    ? Number(spec.volume)
    : track.volume;

  return {
    ...track,
    channelId: track.id,
    label: spec && typeof spec === 'object' && spec.label ? spec.label : track.label,
    volume,
    url: `${base}/${track.file}`,
  };
}

function ambientMixFromSpec(spec, options = {}) {
  if (!spec) return null;
  const base = normalizeBase(options.audioBase || DEFAULT_AMBIENT_AUDIO_BASE);
  if (!base) return null;

  const specs = Array.isArray(spec) ? spec : [spec];
  const tracks = specs
    .map((item) => hydrateTrack(item, base))
    .filter(Boolean);
  if (!tracks.length) return null;

  const firstTrack = tracks[0];
  const label = tracks.map((track) => track.label).join(' + ');
  const id = tracks.length === 1
    ? firstTrack.id
    : `mix:${tracks.map((track) => `${track.id}@${track.volume}`).join('+')}`;

  return {
    ...firstTrack,
    id,
    label,
    tracks,
  };
}

function ambientTrackForVideo(video, options = {}) {
  const id = video && video.id;
  if (Object.prototype.hasOwnProperty.call(AMBIENT_VIDEO_OVERRIDES, id)) {
    return ambientMixFromSpec(AMBIENT_VIDEO_OVERRIDES[id], options);
  }

  const terms = collectTerms(video);
  const rule = AMBIENT_RULES.find((item) => matchesRule(terms, item));
  if (!rule) return null;

  return ambientMixFromSpec(rule.trackId, options);
}

function clampMixVolume(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return 0;
  return Math.max(0, Math.min(1, number));
}

function customAmbientTrackLabel(trackId) {
  return CUSTOM_AMBIENT_LABELS[trackId] || (AMBIENT_TRACKS[trackId] && AMBIENT_TRACKS[trackId].label) || trackId;
}

function customAmbientTrackOptions() {
  return CUSTOM_AMBIENT_TRACK_IDS
    .map((trackId) => {
      const track = AMBIENT_TRACKS[trackId];
      if (!track) return null;
      return {
        id: trackId,
        label: customAmbientTrackLabel(trackId),
      };
    })
    .filter(Boolean);
}

function normalizeCustomAmbientMix(raw) {
  const source = Array.isArray(raw) ? raw : [];
  const normalized = [];
  source.forEach((item) => {
    const trackId = item && item.trackId;
    if (!CUSTOM_AMBIENT_TRACK_IDS.includes(trackId)) return;
    if (normalized.some((track) => track.trackId === trackId)) return;
    if (normalized.length >= MAX_CUSTOM_AMBIENT_TRACKS) return;
    normalized.push({
      trackId,
      volume: clampMixVolume(item.volume),
    });
  });
  return normalized;
}

function ambientMixFromCustomSettings(customMix, options = {}) {
  const specs = normalizeCustomAmbientMix(customMix)
    .filter((item) => item.volume > 0)
    .map((item) => ({
      trackId: item.trackId,
      label: customAmbientTrackLabel(item.trackId),
      volume: item.volume,
    }));

  return ambientMixFromSpec(specs, options);
}

module.exports = {
  AMBIENT_AUDIO_MODES,
  DEFAULT_AMBIENT_AUDIO_BASE,
  AMBIENT_TRACKS,
  MAX_CUSTOM_AMBIENT_TRACKS,
  ambientMixFromCustomSettings,
  ambientMixFromSpec,
  ambientTrackForVideo,
  customAmbientTrackOptions,
  normalizeCustomAmbientMix,
};
