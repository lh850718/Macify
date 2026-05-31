const { getSettings, saveSettings } = require('../../utils/storage.js');
const {
  activeVideoLibrary,
  categoryLabel,
  categoryOptionsForLibrary,
} = require('../../utils/videos.js');
const {
  AMBIENT_AUDIO_MODES,
  MAX_CUSTOM_AMBIENT_TRACKS,
  ambientMixFromCustomSettings,
  customAmbientTrackOptions,
  normalizeCustomAmbientMix,
} = require('../../data/ambient-audio.js');

const AUDITION_AUDIO_CROSSFADE_MS = 6000;
const AUDITION_AUDIO_FADE_STEP_MS = 100;
const AUDITION_AUDIO_STOP_FADE_MS = 800;
const AUDITION_VOLUME_ADJUST_MS = 160;

function clampVolume(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return 0;
  return Math.max(0, Math.min(1, number));
}

function setAudioVolume(audio, volume) {
  if (!audio) return;
  try {
    audio.volume = clampVolume(volume);
  } catch (error) {
    console.warn('Audition volume update failed:', error);
  }
}

function createAuditionAudio(src, volume) {
  if (!wx.createInnerAudioContext) return null;
  let audio = null;
  try {
    audio = wx.createInnerAudioContext({
      useWebAudioImplement: true,
    });
  } catch (error) {
    audio = wx.createInnerAudioContext();
  }
  audio.src = src;
  audio.loop = false;
  audio.volume = clampVolume(volume);
  audio.obeyMuteSwitch = true;
  if (audio.onError) {
    audio.onError((error) => {
      console.warn('Audition audio failed:', error);
    });
  }
  return audio;
}

function auditionLoopDelayMs(track, audio) {
  const durationMs = Number(track && track.durationMs);
  if (!Number.isFinite(durationMs) || durationMs <= 0) return null;
  const currentTime = Number(audio && audio.currentTime);
  const currentMs = Number.isFinite(currentTime) && currentTime > 0
    ? currentTime * 1000
    : 0;
  const remainingMs = Math.max(0, durationMs - currentMs);
  return Math.max(0, remainingMs - AUDITION_AUDIO_CROSSFADE_MS);
}

function categoryIndexFor(value, library) {
  const options = categoryOptionsForLibrary(library);
  const index = options.findIndex((item) => item.value === value);
  return index >= 0 ? index : 0;
}

function categoryOptionsFor(value, library) {
  const options = categoryOptionsForLibrary(library);
  const selected = options.some((item) => item.value === value) ? value : options[0].value;
  return options.map((item) => ({
    ...item,
    selected: item.value === selected,
  }));
}

function customAmbientTracksForSettings(settings) {
  const mix = normalizeCustomAmbientMix(settings.customAmbientMix);
  const selectedCount = mix.length;
  return customAmbientTrackOptions().map((track) => {
    const selected = mix.find((item) => item.trackId === track.id);
    return {
      ...track,
      selected: !!selected,
      disabled: !selected && selectedCount >= MAX_CUSTOM_AMBIENT_TRACKS,
      volumePercent: selected ? Math.round(clampVolume(selected.volume) * 100) : 0,
    };
  });
}

function viewDataForSettings(settings) {
  const library = activeVideoLibrary(settings);
  const customMix = normalizeCustomAmbientMix(settings.customAmbientMix);
  return {
    settings,
    categoryOptions: categoryOptionsFor(settings.shuffleScope, library),
    categoryIndex: categoryIndexFor(settings.shuffleScope, library),
    categoryText: categoryLabel(settings.shuffleScope, library),
    tempIsCelsius: settings.tempUnit === 'celsius',
    tempIsFahrenheit: settings.tempUnit === 'fahrenheit',
    ambientAudioModeIsVideo: settings.ambientAudioMode === AMBIENT_AUDIO_MODES.VIDEO,
    ambientAudioModeIsCustom: settings.ambientAudioMode === AMBIENT_AUDIO_MODES.CUSTOM,
    customAmbientTracks: customAmbientTracksForSettings(settings),
    ambientSelectedCount: customMix.length,
    ambientSelectedLimitText: `${customMix.length}/${MAX_CUSTOM_AMBIENT_TRACKS}`,
  };
}

Page({
  data: {
    settings: {},
    categoryOptions: categoryOptionsFor('all'),
    categoryIndex: 0,
    categoryText: '',
    tempIsCelsius: true,
    tempIsFahrenheit: false,
    ambientAudioModeIsVideo: true,
    ambientAudioModeIsCustom: false,
    customAmbientTracks: [],
    ambientSelectedCount: 0,
    ambientSelectedLimitText: `0/${MAX_CUSTOM_AMBIENT_TRACKS}`,
    ambientAuditionOn: false,
    returnFrom: 'home',
  },

  onLoad(options = {}) {
    this.settingsReturnFrom = options.from === 'zen' ? 'zen' : 'home';
    this.setData({
      returnFrom: this.settingsReturnFrom,
    });
    this.loadSettings();
  },

  onShow() {
    this.loadSettings();
  },

  onHide() {
    this.persistDraftSettings();
    this.stopAuditionAudio();
    if (this.data.ambientAuditionOn) this.setData({ ambientAuditionOn: false });
  },

  onUnload() {
    this.persistDraftSettings();
    this.stopAuditionAudio();
  },

  loadSettings() {
    const settings = getSettings();
    this.setData(viewDataForSettings(settings));
  },

  updateSettings(patch) {
    const next = saveSettings({
      ...this.data.settings,
      ...patch,
    });
    this.setData(viewDataForSettings(next));
    return next;
  },

  persistDraftSettings() {
    const settings = this.data.settings || {};
    if (!settings || !Object.keys(settings).length) return;
    saveSettings({
      ...settings,
      city: String(settings.city || '').trim() || '北京',
    });
  },

  onBreathRhythmInput(event) {
    const rhythm = event.currentTarget.dataset.rhythm;
    const field = event.currentTarget.dataset.field;
    if (!rhythm || !field) return;
    this.setData({
      [`settings.${rhythm}.${field}`]: event.detail.value,
    });
  },

  onBreathRhythmBlur(event) {
    const rhythm = event.currentTarget.dataset.rhythm;
    const field = event.currentTarget.dataset.field;
    if (!rhythm || !field) return;
    this.updateSettings({
      [rhythm]: {
        ...(this.data.settings[rhythm] || {}),
        [field]: event.detail.value,
      },
    });
  },

  onCityInput(event) {
    this.setData({
      'settings.city': event.detail.value,
    });
  },

  onCityBlur(event) {
    this.updateSettings({
      city: event.detail.value.trim() || '北京',
    });
  },

  onTempUnitChange(event) {
    this.updateSettings({
      tempUnit: event.detail.value,
    });
  },

  onAmbientAudioModeChange(event) {
    const mode = event.detail.value === AMBIENT_AUDIO_MODES.CUSTOM
      ? AMBIENT_AUDIO_MODES.CUSTOM
      : AMBIENT_AUDIO_MODES.VIDEO;
    this.updateSettings({
      ambientAudioMode: mode,
    });
    if (mode !== AMBIENT_AUDIO_MODES.CUSTOM) {
      this.stopAuditionAudio();
      if (this.data.ambientAuditionOn) this.setData({ ambientAuditionOn: false });
    }
  },

  onCustomTrackTap(event) {
    const trackId = event.currentTarget.dataset.trackId;
    if (!trackId) return;
    const mix = normalizeCustomAmbientMix(this.data.settings.customAmbientMix);
    const index = mix.findIndex((item) => item.trackId === trackId);

    if (index >= 0) {
      mix.splice(index, 1);
    } else if (mix.length >= MAX_CUSTOM_AMBIENT_TRACKS) {
      wx.showToast({
        title: `最多选择 ${MAX_CUSTOM_AMBIENT_TRACKS} 个声音`,
        icon: 'none',
        duration: 1400,
      });
      return;
    } else {
      mix.push({
        trackId,
        volume: 0,
      });
    }

    this.updateCustomAmbientMix(mix, true);
  },

  onCustomTrackVolumeChanging(event) {
    this.updateCustomTrackVolume(event, false);
  },

  onCustomTrackVolumeChange(event) {
    this.updateCustomTrackVolume(event, true);
  },

  updateCustomTrackVolume(event, persist) {
    const trackId = event.currentTarget.dataset.trackId;
    if (!trackId) return;
    const value = Math.max(0, Math.min(100, Math.round(Number(event.detail.value) || 0)));
    const mix = normalizeCustomAmbientMix(this.data.settings.customAmbientMix);
    const index = mix.findIndex((item) => item.trackId === trackId);
    if (index < 0) return;
    mix[index] = {
      ...mix[index],
      volume: value / 100,
    };

    this.updateCustomAmbientMix(mix, persist);
  },

  updateCustomAmbientMix(mix, persist) {
    const normalized = normalizeCustomAmbientMix(mix);
    const settings = {
      ...this.data.settings,
      customAmbientMix: normalized,
    };
    const next = persist ? saveSettings(settings) : settings;
    this.setData(viewDataForSettings(next), () => {
      if (this.data.ambientAuditionOn) this.syncAuditionAudio();
    });
  },

  toggleAmbientAudition() {
    if (this.data.ambientAuditionOn) {
      this.setData({ ambientAuditionOn: false });
      this.fadeOutAuditionAudio();
      return;
    }

    const mix = normalizeCustomAmbientMix(this.data.settings.customAmbientMix);
    if (!mix.length) {
      wx.showToast({
        title: '先选择一个声音',
        icon: 'none',
        duration: 1300,
      });
      return;
    }

    this.setData({ ambientAuditionOn: true }, () => {
      this.syncAuditionAudio();
      if (!ambientMixFromCustomSettings(this.data.settings.customAmbientMix)) {
        wx.showToast({
          title: '拖动音量开始试听',
          icon: 'none',
          duration: 1400,
        });
      }
    });
  },

  onCategoryChange(event) {
    const index = Number(event.detail.value);
    const options = categoryOptionsForLibrary(activeVideoLibrary(this.data.settings || {}));
    const option = options[index] || options[0];
    this.updateSettings({
      shuffleScope: option.value,
    });
  },

  onCategoryTap(event) {
    const options = categoryOptionsForLibrary(activeVideoLibrary(this.data.settings || {}));
    const value = event.currentTarget.dataset.value || options[0].value;
    this.updateSettings({
      shuffleScope: value,
    });
  },

  onSwitchChange(event) {
    const key = event.currentTarget.dataset.key;
    this.updateSettings({
      [key]: event.detail.value,
    });
  },

  openLicenses() {
    wx.navigateTo({
      url: '/pages/licenses/licenses',
    });
  },

  saveAndReturn() {
    this.persistDraftSettings();
    this.stopAuditionAudio();
    if (this.data.ambientAuditionOn) this.setData({ ambientAuditionOn: false });

    const pages = typeof getCurrentPages === 'function' ? getCurrentPages() : [];
    if (pages.length > 1) {
      wx.navigateBack({ delta: 1 });
      return;
    }

    const mode = this.settingsReturnFrom === 'zen' ? 'zen' : 'home';
    wx.redirectTo({
      url: `/pages/index/index${mode === 'zen' ? '?mode=zen' : ''}`,
    });
  },

  syncAuditionAudio() {
    if (!this.data.ambientAuditionOn) return;
    const track = ambientMixFromCustomSettings(this.data.settings.customAmbientMix);
    if (!track) {
      this.fadeOutAuditionAudio();
      return;
    }
    this.switchAuditionTrack(track);
  },

  switchAuditionTrack(track) {
    if (this.auditionAudioFadeTimer) {
      clearInterval(this.auditionAudioFadeTimer);
      this.auditionAudioFadeTimer = null;
    }

    const tracks = this.auditionTracksForMix(track);
    if (!tracks.length) return;

    const activeKeys = {};
    tracks.forEach((item) => {
      const key = this.auditionAudioChannelKey(item);
      if (key) activeKeys[key] = true;
    });

    Object.keys(this.auditionAudioChannels || {}).forEach((key) => {
      if (!activeKeys[key]) this.fadeOutAuditionChannel(key);
    });

    tracks.forEach((item) => this.switchAuditionChannelTrack(item));
  },

  auditionTracksForMix(track) {
    if (!track) return [];
    if (Array.isArray(track.tracks)) return track.tracks.filter((item) => item && item.url);
    return track.url ? [track] : [];
  },

  auditionAudioChannelKey(track) {
    if (!track) return '';
    return track.channelId || track.id || track.file || '';
  },

  ensureAuditionAudioChannel(key) {
    if (!this.auditionAudioChannels) this.auditionAudioChannels = {};
    if (!this.auditionAudioChannels[key]) {
      this.auditionAudioChannels[key] = {
        key,
        current: null,
        nextTimer: null,
        fadeTimer: null,
        targetVolume: 0,
        track: null,
      };
    }
    return this.auditionAudioChannels[key];
  },

  switchAuditionChannelTrack(track) {
    const key = this.auditionAudioChannelKey(track);
    if (!key || !track.url) return;

    const channel = this.ensureAuditionAudioChannel(key);
    const targetVolume = clampVolume(track.volume);
    channel.track = track;
    channel.targetVolume = targetVolume;

    if (channel.current) {
      channel.current.__auditionTrack = track;
      channel.current.__auditionTargetVolume = targetVolume;
      this.destroyAuditionChannelInactivePlayers(key);
      this.scheduleAuditionAudioCrossfade(key, channel.current);
      this.fadeAuditionChannelToVolume(key, targetVolume, AUDITION_VOLUME_ADJUST_MS);
      return;
    }

    const next = this.startAuditionAudioTrack(track, 0, key);
    if (!next) return;

    channel.current = next;
    this.scheduleAuditionAudioCrossfade(key, next);
    this.fadeAuditionChannelToVolume(key, targetVolume, AUDITION_AUDIO_CROSSFADE_MS);
  },

  startAuditionAudioTrack(track, volume, channelKey) {
    const audio = createAuditionAudio(track.url, volume);
    if (!audio) return null;

    audio.__auditionTrack = track;
    audio.__auditionChannelKey = channelKey;
    audio.__auditionTargetVolume = clampVolume(track.volume);
    audio.__auditionLastVolume = clampVolume(volume);
    audio.__auditionCrossfadeStarted = false;
    this.auditionAudioPlayers = this.auditionAudioPlayers || [];
    this.auditionAudioPlayers.push(audio);

    if (audio.onTimeUpdate) {
      audio.onTimeUpdate(() => {
        const channel = this.auditionAudioChannels && this.auditionAudioChannels[channelKey];
        if (!channel || audio !== channel.current || audio.__auditionCrossfadeStarted) return;
        const duration = Number(audio.duration) || (track.durationMs || 0) / 1000;
        if (duration && audio.currentTime >= duration - AUDITION_AUDIO_CROSSFADE_MS / 1000) {
          this.crossfadeAuditionAudio(channelKey);
        }
      });
    }

    if (audio.onEnded) {
      audio.onEnded(() => {
        const channel = this.auditionAudioChannels && this.auditionAudioChannels[channelKey];
        if (!channel || audio !== channel.current) return;
        if (!this.data.ambientAuditionOn) return;
        this.crossfadeAuditionAudio(channelKey, true);
      });
    }

    try {
      if (audio.seek) audio.seek(0);
      audio.play();
    } catch (error) {
      console.warn('Audition playback failed:', error);
    }
    return audio;
  },

  scheduleAuditionAudioCrossfade(channelKey, audio) {
    const channel = this.auditionAudioChannels && this.auditionAudioChannels[channelKey];
    if (!channel) return;
    this.clearAuditionChannelNextTimer(channel);
    const track = audio && audio.__auditionTrack;
    const delayMs = auditionLoopDelayMs(track, audio);
    if (delayMs == null) return;
    channel.nextTimer = setTimeout(() => {
      const currentChannel = this.auditionAudioChannels && this.auditionAudioChannels[channelKey];
      if (currentChannel && audio === currentChannel.current) this.crossfadeAuditionAudio(channelKey);
    }, delayMs);
  },

  crossfadeAuditionAudio(channelKey, immediate = false) {
    if (!this.data.ambientAuditionOn) return;
    const channel = this.auditionAudioChannels && this.auditionAudioChannels[channelKey];
    if (!channel) return;
    const previous = channel.current;
    const track = channel.track || (previous && previous.__auditionTrack);
    if (!track) return;
    if (previous && previous.__auditionCrossfadeStarted) return;
    if (previous) previous.__auditionCrossfadeStarted = true;

    const next = this.startAuditionAudioTrack(track, immediate ? channel.targetVolume : 0, channelKey);
    if (!next) return;

    channel.current = next;
    this.scheduleAuditionAudioCrossfade(channelKey, next);

    if (immediate || !previous) {
      this.destroyAuditionAudio(previous);
      setAudioVolume(next, channel.targetVolume);
      return;
    }

    this.fadeAuditionAudioPair(
      channelKey,
      previous,
      next,
      previous.__auditionLastVolume == null ? previous.__auditionTargetVolume : previous.__auditionLastVolume,
      channel.targetVolume,
      AUDITION_AUDIO_CROSSFADE_MS,
    );
  },

  fadeAuditionAudioPair(channelKey, previous, next, previousVolume, nextVolume, durationMs) {
    const channel = this.auditionAudioChannels && this.auditionAudioChannels[channelKey];
    if (!channel) return;
    this.clearAuditionChannelFadeTimer(channel);
    const steps = Math.max(1, Math.ceil(durationMs / AUDITION_AUDIO_FADE_STEP_MS));
    let step = 0;

    channel.fadeTimer = setInterval(() => {
      step += 1;
      const progress = Math.min(1, step / steps);
      const previousNextVolume = clampVolume(previousVolume * (1 - progress));
      const nextNextVolume = clampVolume(nextVolume * progress);
      if (previous) {
        previous.__auditionLastVolume = previousNextVolume;
        setAudioVolume(previous, previousNextVolume);
      }
      if (next) {
        next.__auditionLastVolume = nextNextVolume;
        setAudioVolume(next, nextNextVolume);
      }

      if (progress < 1) return;
      this.clearAuditionChannelFadeTimer(channel);
      this.destroyAuditionAudio(previous);
      if (next) {
        next.__auditionLastVolume = clampVolume(nextVolume);
        setAudioVolume(next, next.__auditionLastVolume);
      }
    }, AUDITION_AUDIO_FADE_STEP_MS);
  },

  fadeAuditionChannelToVolume(channelKey, targetVolume, durationMs) {
    const channel = this.auditionAudioChannels && this.auditionAudioChannels[channelKey];
    const audio = channel && channel.current;
    if (!channel || !audio) return;

    const startVolume = audio.__auditionLastVolume == null ? audio.__auditionTargetVolume || 0 : audio.__auditionLastVolume;
    const endVolume = clampVolume(targetVolume);
    audio.__auditionTargetVolume = endVolume;
    if (Math.abs(startVolume - endVolume) < 0.01) {
      audio.__auditionLastVolume = endVolume;
      setAudioVolume(audio, endVolume);
      return;
    }

    this.clearAuditionChannelFadeTimer(channel);
    const steps = Math.max(1, Math.ceil(durationMs / AUDITION_AUDIO_FADE_STEP_MS));
    let step = 0;

    channel.fadeTimer = setInterval(() => {
      step += 1;
      const progress = Math.min(1, step / steps);
      const nextVolume = clampVolume(startVolume + (endVolume - startVolume) * progress);
      audio.__auditionLastVolume = nextVolume;
      setAudioVolume(audio, nextVolume);

      if (progress < 1) return;
      this.clearAuditionChannelFadeTimer(channel);
      audio.__auditionLastVolume = endVolume;
      setAudioVolume(audio, endVolume);
    }, AUDITION_AUDIO_FADE_STEP_MS);
  },

  fadeOutAuditionChannel(channelKey) {
    const channel = this.auditionAudioChannels && this.auditionAudioChannels[channelKey];
    if (!channel) return;
    this.clearAuditionChannelNextTimer(channel);
    this.clearAuditionChannelFadeTimer(channel);

    const players = (this.auditionAudioPlayers || []).filter((audio) => audio.__auditionChannelKey === channelKey);
    if (!players.length) {
      delete this.auditionAudioChannels[channelKey];
      return;
    }

    const startVolumes = players.map((audio) => (
      audio.__auditionLastVolume == null ? audio.__auditionTargetVolume || 0 : audio.__auditionLastVolume
    ));
    const steps = Math.max(1, Math.ceil(AUDITION_AUDIO_STOP_FADE_MS / AUDITION_AUDIO_FADE_STEP_MS));
    let step = 0;

    channel.fadeTimer = setInterval(() => {
      step += 1;
      const progress = Math.min(1, step / steps);
      players.forEach((audio, index) => {
        const nextVolume = clampVolume(startVolumes[index] * (1 - progress));
        audio.__auditionLastVolume = nextVolume;
        setAudioVolume(audio, nextVolume);
      });

      if (progress < 1) return;
      this.clearAuditionChannelFadeTimer(channel);
      players.forEach((audio) => this.destroyAuditionAudio(audio));
      delete this.auditionAudioChannels[channelKey];
    }, AUDITION_AUDIO_FADE_STEP_MS);
  },

  destroyAuditionChannelInactivePlayers(channelKey) {
    const channel = this.auditionAudioChannels && this.auditionAudioChannels[channelKey];
    if (!channel) return;
    (this.auditionAudioPlayers || [])
      .filter((audio) => audio.__auditionChannelKey === channelKey && audio !== channel.current)
      .forEach((audio) => this.destroyAuditionAudio(audio));
  },

  fadeOutAuditionAudio() {
    this.clearAuditionAudioNextTimer();
    this.clearAuditionAudioFadeTimer();
    const players = (this.auditionAudioPlayers || []).slice();
    if (!players.length) {
      this.auditionAudioChannels = {};
      return;
    }
    const startVolumes = players.map((audio) => (
      audio.__auditionLastVolume == null ? audio.__auditionTargetVolume || 0 : audio.__auditionLastVolume
    ));
    const steps = Math.max(1, Math.ceil(AUDITION_AUDIO_STOP_FADE_MS / AUDITION_AUDIO_FADE_STEP_MS));
    let step = 0;

    this.auditionAudioFadeTimer = setInterval(() => {
      step += 1;
      const progress = Math.min(1, step / steps);
      players.forEach((audio, index) => {
        const nextVolume = clampVolume(startVolumes[index] * (1 - progress));
        audio.__auditionLastVolume = nextVolume;
        setAudioVolume(audio, nextVolume);
      });

      if (progress < 1) return;
      this.clearAuditionAudioFadeTimer();
      players.forEach((audio) => this.destroyAuditionAudio(audio));
      this.auditionAudioChannels = {};
    }, AUDITION_AUDIO_FADE_STEP_MS);
  },

  stopAuditionAudio() {
    this.clearAuditionAudioTimers();
    const players = this.auditionAudioPlayers || [];
    players.forEach((audio) => this.destroyAuditionAudio(audio));
    this.auditionAudioPlayers = [];
    this.auditionAudioChannels = {};
  },

  clearAuditionAudioTimers() {
    this.clearAuditionAudioNextTimer();
    this.clearAuditionAudioFadeTimer();
  },

  clearAuditionAudioNextTimer() {
    Object.keys(this.auditionAudioChannels || {}).forEach((key) => {
      this.clearAuditionChannelNextTimer(this.auditionAudioChannels[key]);
    });
  },

  clearAuditionAudioFadeTimer() {
    if (this.auditionAudioFadeTimer) {
      clearInterval(this.auditionAudioFadeTimer);
      this.auditionAudioFadeTimer = null;
    }
    Object.keys(this.auditionAudioChannels || {}).forEach((key) => {
      this.clearAuditionChannelFadeTimer(this.auditionAudioChannels[key]);
    });
  },

  clearAuditionChannelNextTimer(channel) {
    if (channel && channel.nextTimer) {
      clearTimeout(channel.nextTimer);
      channel.nextTimer = null;
    }
  },

  clearAuditionChannelFadeTimer(channel) {
    if (channel && channel.fadeTimer) {
      clearInterval(channel.fadeTimer);
      channel.fadeTimer = null;
    }
  },

  destroyAuditionAudio(audio) {
    if (!audio) return;
    try {
      audio.stop();
      audio.destroy();
    } catch (error) {
      console.warn('Audition audio cleanup failed:', error);
    }
    this.auditionAudioPlayers = (this.auditionAudioPlayers || []).filter((item) => item !== audio);
  },
});
