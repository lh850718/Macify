const VIDEO_AMBIENT_MIXES = require('./video-audio-mixes.js');
const {
  AMBIENT_AUDIO_MODES,
  AMBIENT_RULES,
  AMBIENT_TRACKS,
  CUSTOM_AMBIENT_LABELS,
  CUSTOM_AMBIENT_TRACK_IDS,
  DEFAULT_AMBIENT_AUDIO_BASE,
  MAX_CUSTOM_AMBIENT_TRACKS,
} = require('./ambient-content.js');

const AMBIENT_VIDEO_OVERRIDES = Object.freeze(
  VIDEO_AMBIENT_MIXES.reduce((result, item) => {
    if (!item || !item.videoId) return result;
    result[item.videoId] = item.mix == null ? null : item.mix;
    return result;
  }, {}),
);

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
  return matches.some((match) => terms.includes(String(match).trim().toLowerCase()));
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
  AMBIENT_RULES,
  DEFAULT_AMBIENT_AUDIO_BASE,
  AMBIENT_TRACKS,
  CUSTOM_AMBIENT_LABELS,
  CUSTOM_AMBIENT_TRACK_IDS,
  MAX_CUSTOM_AMBIENT_TRACKS,
  VIDEO_AMBIENT_MIXES,
  ambientMixFromCustomSettings,
  ambientMixFromSpec,
  ambientTrackForVideo,
  customAmbientTrackOptions,
  normalizeCustomAmbientMix,
};
