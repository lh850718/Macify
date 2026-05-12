const {
  getSettings,
  isFavoriteVideo,
  setSetting,
  toggleFavoriteVideo,
} = require('../../utils/storage.js');
const { pickQuote } = require('../../utils/quotes.js');
const { pickVideo, videoById } = require('../../utils/videos.js');
const { cacheVideo, cachedVideoForSettings } = require('../../utils/video-cache.js');
const { getForecast, describeWeather } = require('../../utils/weather.js');
const videoIntros = require('../../data/video-intros.js');

const BREATH_PHASE_MS = 5000;
const HAPTIC_LEAD_MS = 850;
const ZEN_AUDIO_SOURCE = '/assets/breath.mp3';
const ZEN_AUDIO_VOLUME = 0.55;
const ZEN_AUDIO_FALLBACK_DURATION_MS = 63384;
const ZEN_AUDIO_CROSSFADE_MS = 2200;
const ZEN_AUDIO_FADE_STEP_MS = 100;
const VIDEO_REVEAL_MS = 520;
const FAVORITE_TOAST_TEXT = '已经收藏，可以在设置页选择收藏分类播放收藏视频';
const WEEKDAY_LABELS = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
const HAPTIC_PATTERNS = {
  inhale: [
    { at: 0, type: 'light' },
    { at: 320, type: 'light' },
    { at: 620, type: 'light' },
    { at: 900, type: 'light' },
    { at: 1160, type: 'light' },
    { at: 1400, type: 'light' },
    { at: 1620, type: 'medium' },
    { at: 1830, type: 'medium' },
    { at: 2050, type: 'medium' },
    { at: 2300, type: 'medium' },
    { at: 2580, type: 'medium' },
    { at: 2890, type: 'heavy' },
    { at: 3230, type: 'heavy' },
    { at: 3590, type: 'heavy' },
    { at: 3970, type: 'heavy' },
  ],
};

function pad(value) {
  return String(value).padStart(2, '0');
}

function formatDate(date) {
  const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  return `${weekdays[date.getDay()]} ${date.getFullYear()}.${pad(date.getMonth() + 1)}.${pad(date.getDate())}`;
}

function vibrateShort(type) {
  if (!wx.vibrateShort) return;
  const fallback = () => {
    try {
      wx.vibrateShort({});
    } catch (error) {
      console.warn('Vibrate fallback failed:', error);
    }
  };
  try {
    wx.vibrateShort({
      type,
      fail: fallback,
    });
  } catch (error) {
    fallback();
  }
}

function clampVolume(value) {
  return Math.max(0, Math.min(ZEN_AUDIO_VOLUME, value));
}

function setAudioVolume(audio, volume) {
  if (!audio) return;
  try {
    audio.volume = clampVolume(volume);
  } catch (error) {
    console.warn('Zen cue volume update failed:', error);
  }
}

function createZenAudio(src, volume) {
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
      console.warn('Zen cue audio failed:', error);
    });
  }
  return audio;
}

function otherVideoSlot(slot) {
  return slot === 'b' ? 'a' : 'b';
}

function slotVideoKey(slot) {
  return slot === 'b' ? 'videoSlotB' : 'videoSlotA';
}

function slotReadyKey(slot) {
  return slot === 'b' ? 'videoSlotBReady' : 'videoSlotAReady';
}

function sameVideo(left, right) {
  return left
    && right
    && left.id === right.id
    && left.videoLibrary === right.videoLibrary
    && left.url === right.url;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function windowWidth() {
  try {
    if (wx.getWindowInfo) return wx.getWindowInfo().windowWidth;
    return wx.getSystemInfoSync().windowWidth;
  } catch (error) {
    return 375;
  }
}

function touchPointFromEvent(event, fallbackSide) {
  const touch = event
    && ((event.touches && event.touches[0]) || (event.changedTouches && event.changedTouches[0]));
  const width = windowWidth();
  return {
    x: touch && typeof touch.clientX === 'number' ? touch.clientX : fallbackSide === 'right' ? width - 32 : 32,
    y: touch && typeof touch.clientY === 'number' ? touch.clientY : 72,
  };
}

function anchoredPopoverStyle(event, side = 'left') {
  const width = windowWidth();
  const margin = Math.max(14, width * 28 / 750);
  const popoverWidth = Math.min(width - margin * 2, width * 620 / 750);
  const point = touchPointFromEvent(event, side);
  const top = Math.max(12, point.y + 12);

  if (side === 'right') {
    const right = clamp(width - point.x - margin, margin, width - popoverWidth - margin);
    return `top:${top}px;right:${right}px;left:auto;`;
  }

  const left = clamp(point.x - margin, margin, width - popoverWidth - margin);
  return `top:${top}px;left:${left}px;right:auto;`;
}

function dailyLabel(dateText, index) {
  if (index === 0) return '今天';
  if (index === 1) return '明天';
  const date = new Date(`${dateText}T00:00:00`);
  if (Number.isNaN(date.getTime())) return `第 ${index + 1} 天`;
  return WEEKDAY_LABELS[date.getDay()];
}

function timeOnly(value) {
  const text = String(value || '');
  return text.includes('T') ? text.split('T')[1].slice(0, 5) : '';
}

function playbackSettingsKey(settings) {
  return [
    settings.videoSource,
    settings.videoLibrary,
    settings.shuffleScope,
    settings.liteVideoBase,
    settings.premiumFreeAerialVideoBase,
    settings.reverseProxy ? 'proxy' : 'direct',
    settings.proxyBase,
  ].join('|');
}

Page({
  data: {
    settings: {},
    currentVideo: null,
    currentQuote: null,
    clock: '',
    dateText: '',
    forecast: null,
    weatherLabel: '',
    weatherVisible: false,
    weatherDaily: [],
    videoIntroVisible: false,
    currentVideoIntro: null,
    currentVideoFavorited: false,
    weatherPopoverStyle: '',
    videoIntroPopoverStyle: '',
    videoReady: false,
    videoSlotA: null,
    videoSlotB: null,
    videoSlotAReady: false,
    videoSlotBReady: false,
    activeVideoSlot: 'a',
    incomingVideoSlot: '',
    videoTransitionPoster: '',
    videoTransitionStage: 'idle',
    videoFallbackUsed: false,
    zenActive: false,
    zenHintText: '',
    videoError: '',
  },

  onLoad() {
    this.loadSettingsAndContent();
    this.startClock();
  },

  onShow() {
    this.loadSettingsAndContent();
  },

  onUnload() {
    if (this.clockTimer) clearInterval(this.clockTimer);
    this.abortVideoCacheDownload();
    this.clearVideoTransitionTimer();
    this.stopZenCues();
  },

  onHide() {
    this.stopZenCues();
  },

  onPullDownRefresh() {
    this.nextVideo();
    this.nextQuote();
    this.loadWeather();
    wx.stopPullDownRefresh();
  },

  startClock() {
    this.updateClock();
    this.clockTimer = setInterval(() => this.updateClock(), 30 * 1000);
  },

  updateClock() {
    const now = new Date();
    this.setData({
      clock: `${pad(now.getHours())}:${pad(now.getMinutes())}`,
      dateText: formatDate(now),
    });
  },

  loadSettingsAndContent() {
    const settings = getSettings();
    const nextPlaybackKey = playbackSettingsKey(settings);
    const playbackChanged = this.playbackSettingsKey && this.playbackSettingsKey !== nextPlaybackKey;
    this.playbackSettingsKey = nextPlaybackKey;

    this.setData(
      {
        settings,
      },
      () => {
        if (!this.data.currentVideo) this.restoreCachedOrNextVideo();
        else if (playbackChanged) this.nextVideo();
        if (!this.data.currentQuote) this.nextQuote();
        this.loadWeather();
        if (this.data.zenActive && !this.zenPhaseTimer) {
          this.startZenCues();
        }
      },
    );
  },

  setCurrentVideo(next, options = {}) {
    const current = this.data.currentVideo;
    const activeSlot = this.data.activeVideoSlot || 'a';
    const shouldTransition = current && next && current.url && next.url && !sameVideo(current, next);
    const videoData = {
      currentVideo: next,
      currentVideoIntro: next ? next.description || videoIntros[next.originalName || next.name] || '' : '',
      currentVideoFavorited: next ? isFavoriteVideo(next) : false,
      videoIntroVisible: false,
      videoReady: false,
      videoFallbackUsed: false,
      videoError: next && next.warning ? next.warning : '',
    };
    const afterVideoSet = () => {
      if (next && !options.skipCache) this.cacheCurrentVideo(next);
    };

    this.clearVideoTransitionTimer();

    if (!next) {
      this.setData({
        ...videoData,
        videoSlotA: null,
        videoSlotB: null,
        videoSlotAReady: false,
        videoSlotBReady: false,
        activeVideoSlot: 'a',
        incomingVideoSlot: '',
        videoTransitionPoster: '',
        videoTransitionStage: 'idle',
      });
      return;
    }

    if (shouldTransition) {
      const incomingSlot = otherVideoSlot(activeSlot);
      this.setData({
        ...videoData,
        [slotVideoKey(incomingSlot)]: next,
        [slotReadyKey(incomingSlot)]: false,
        incomingVideoSlot: incomingSlot,
        videoTransitionPoster: next.poster || '',
        videoTransitionStage: 'loading',
      }, afterVideoSet);
      return;
    }

    this.setData({
      ...videoData,
      videoSlotA: next,
      videoSlotAReady: false,
      videoSlotB: null,
      videoSlotBReady: false,
      activeVideoSlot: 'a',
      incomingVideoSlot: '',
      videoTransitionPoster: '',
      videoTransitionStage: 'idle',
    }, afterVideoSet);
  },

  clearVideoTransitionTimer() {
    if (this.videoTransitionTimer) {
      clearTimeout(this.videoTransitionTimer);
      this.videoTransitionTimer = null;
    }
  },

  activateIncomingVideo(slot) {
    const previousSlot = this.data.activeVideoSlot || 'a';
    this.clearVideoTransitionTimer();

    this.setData({
      activeVideoSlot: slot,
      incomingVideoSlot: '',
      videoReady: true,
      [slotReadyKey(slot)]: true,
      videoTransitionStage: 'revealing',
    }, () => {
      this.videoTransitionTimer = setTimeout(() => {
        const staleSlot = previousSlot === slot ? otherVideoSlot(slot) : previousSlot;
        this.setData({
          [slotVideoKey(staleSlot)]: null,
          [slotReadyKey(staleSlot)]: false,
          videoTransitionPoster: '',
          videoTransitionStage: 'idle',
        });
        this.videoTransitionTimer = null;
      }, VIDEO_REVEAL_MS);
    });
  },

  videoForSlot(slot) {
    return slot === 'b' ? this.data.videoSlotB : this.data.videoSlotA;
  },

  onVideoPlay(event) {
    const slot = event.currentTarget.dataset.slot || 'a';
    if (slot === this.data.incomingVideoSlot) {
      this.activateIncomingVideo(slot);
      return;
    }

    this.setData({
      [slotReadyKey(slot)]: true,
      videoReady: slot === this.data.activeVideoSlot ? true : this.data.videoReady,
    });
  },

  onVideoError(error) {
    console.warn('Video load failed:', error);
    const slot = error.currentTarget && error.currentTarget.dataset
      ? error.currentTarget.dataset.slot || this.data.activeVideoSlot || 'a'
      : this.data.activeVideoSlot || 'a';
    if (slot !== this.data.activeVideoSlot && slot !== this.data.incomingVideoSlot) return;
    if (this.data.incomingVideoSlot && slot === this.data.activeVideoSlot) return;
    const failedVideo = this.videoForSlot(slot) || this.data.currentVideo;

    if (failedVideo && failedVideo.fallbackUrl && !this.data.videoFallbackUsed) {
      const isPremium = failedVideo.videoLibrary === 'premiumFreeAerial';
      const fallbackVideo = {
        ...failedVideo,
        url: failedVideo.fallbackUrl,
        fallbackUrl: '',
      };
      this.setData({
        currentVideo: fallbackVideo,
        [slotVideoKey(slot)]: fallbackVideo,
        [slotReadyKey(slot)]: false,
        videoReady: slot === this.data.activeVideoSlot ? false : this.data.videoReady,
        videoFallbackUsed: true,
        videoError: isPremium ? '高端免费航拍加载失败，正在尝试源站回退' : '轻量视频加载失败，正在回退 Apple 1080 源',
      });
      return;
    }

    this.setData({
      videoError: '视频加载失败，已切换下一条',
    });
    setTimeout(() => this.nextVideo(), 700);
  },

  restoreCachedOrNextVideo() {
    const settings = this.data.settings && this.data.settings.city ? this.data.settings : getSettings();
    const cached = cachedVideoForSettings(settings, (candidateSettings, id) => videoById(candidateSettings, id));
    if (cached) {
      this.setCurrentVideo(cached, { skipCache: true });
      return;
    }
    this.nextVideo();
  },

  nextVideo() {
    const settings = this.data.settings && this.data.settings.city ? this.data.settings : getSettings();
    const currentId = this.data.currentVideo && this.data.currentVideo.id;
    const next = pickVideo(settings, currentId);
    if (!next) {
      this.setData({
        videoError: settings.shuffleScope === 'favorites'
          ? '还没有收藏视频，请先在左上角介绍里点爱心收藏'
          : '当前播放范围暂无视频',
      });
      return;
    }
    this.setCurrentVideo(next);
  },

  abortVideoCacheDownload() {
    if (this.videoCacheDownloadTask && this.videoCacheDownloadTask.abort) {
      this.videoCacheDownloadTask.abort();
    }
    this.videoCacheDownloadTask = null;
    this.videoCacheToken = '';
  },

  cacheCurrentVideo(video) {
    const settings = this.data.settings && this.data.settings.city ? this.data.settings : getSettings();
    this.abortVideoCacheDownload();

    const token = `${video.videoLibrary || 'apple'}:${video.id}:${Date.now()}`;
    this.videoCacheToken = token;
    this.videoCacheDownloadTask = cacheVideo(settings, video, {
      success: (meta) => {
        if (this.videoCacheToken !== token) return;
        const current = this.data.currentVideo;
        if (!current || current.id !== video.id || current.videoLibrary !== meta.videoLibrary) return;
        // Keep the active src stable; swapping to the cached file restarts WeChat video playback.
        this.videoCacheDownloadTask = null;
      },
      fail: (error) => {
        console.warn('Video cache download failed:', error);
      },
    });
  },

  nextQuote() {
    const current = this.data.currentQuote && this.data.currentQuote.content;
    this.setData({
      currentQuote: pickQuote(current),
    });
  },

  loadWeather() {
    const settings = this.data.settings && this.data.settings.city ? this.data.settings : getSettings();
    if (!settings.showWeather || !settings.city) {
      this.setData({
        forecast: null,
        weatherLabel: '',
      });
      return;
    }

    getForecast({
      city: settings.city,
      tempUnit: settings.tempUnit,
    })
      .then((forecast) => {
        this.setData({
          forecast,
          weatherLabel: describeWeather(forecast.current.weatherCode),
          weatherDaily: (forecast.daily || []).map((day, index) => ({
            ...day,
            label: dailyLabel(day.date, index),
            dateShort: day.date ? day.date.slice(5).replace('-', '/') : '',
            weatherText: describeWeather(day.weatherCode),
            precipitationText: day.precipitation == null ? 0 : day.precipitation,
            precipitationSumText: day.precipitationSum == null ? 0 : day.precipitationSum,
            windSpeedText: day.windSpeed == null ? 0 : day.windSpeed,
            uvIndexText: day.uvIndex == null ? 0 : day.uvIndex,
            sunriseText: timeOnly(day.sunrise),
            sunsetText: timeOnly(day.sunset),
          })),
        });
      })
      .catch((error) => {
        console.warn('Weather load failed:', error);
        this.setData({
          forecast: null,
          weatherLabel: '',
          weatherVisible: false,
          weatherDaily: [],
        });
      });
  },

  toggleWeather(event) {
    if (!this.data.forecast) return;
    this.setData({
      weatherVisible: !this.data.weatherVisible,
      videoIntroVisible: false,
      weatherPopoverStyle: anchoredPopoverStyle(event, 'right'),
    });
  },

  closeWeather() {
    this.setData({
      weatherVisible: false,
    });
  },

  openVideoIntro(event) {
    if (!this.data.currentVideo) return;
    this.setData({
      videoIntroVisible: true,
      weatherVisible: false,
      videoIntroPopoverStyle: anchoredPopoverStyle(event, 'left'),
    });
  },

  closeVideoIntro() {
    this.setData({
      videoIntroVisible: false,
    });
  },

  toggleFavorite() {
    if (!this.data.currentVideo) return;
    const result = toggleFavoriteVideo(this.data.currentVideo);
    this.setData({
      currentVideoFavorited: result.favorited,
    });
    wx.showToast({
      title: result.favorited ? FAVORITE_TOAST_TEXT : '已取消收藏',
      icon: 'none',
      duration: result.favorited ? 2600 : 1500,
    });
  },

  enterZen() {
    this.setData({
      zenActive: true,
      weatherVisible: false,
    }, () => {
      this.startZenCues();
    });
  },

  exitZen() {
    this.stopZenCues();
    this.setData({
      zenActive: false,
    });
  },

  toggleZenHaptics() {
    const settings = setSetting('zenHaptics', !this.data.settings.zenHaptics);
    this.setData({ settings });
    if (settings.zenHaptics) {
      this.showZenHint('需要打开手机振动功能');
      if (this.zenPhase === 'inhale') {
        this.playZenHaptics();
      } else {
        this.scheduleZenHapticLead();
      }
    } else {
      this.zenHapticLeadArmed = false;
      this.clearZenHapticTimers();
    }
  },

  toggleZenSound() {
    const settings = setSetting('zenSound', !this.data.settings.zenSound);
    this.setData({ settings });
    if (settings.zenSound) {
      this.playZenSound();
    } else {
      this.stopZenAudio();
    }
  },

  startZenCues() {
    this.clearZenPhaseTimer();
    this.clearZenHapticTimers();
    this.startZenPhase('inhale');
    if (this.data.settings.zenSound) this.playZenSound();
  },

  stopZenCues() {
    this.clearZenPhaseTimer();
    this.clearZenHapticTimers();
    this.clearZenHintTimer();
    this.setData({ zenHintText: '' });
    this.stopZenAudio();
    this.zenPhase = null;
    this.zenHapticLeadArmed = false;
  },

  clearZenPhaseTimer() {
    if (this.zenPhaseTimer) {
      clearTimeout(this.zenPhaseTimer);
      this.zenPhaseTimer = null;
    }
  },

  clearZenHapticTimers() {
    if (!this.zenHapticTimers) {
      this.zenHapticTimers = [];
      return;
    }
    this.zenHapticTimers.forEach((timer) => clearTimeout(timer));
    this.zenHapticTimers = [];
  },

  clearZenHintTimer() {
    if (this.zenHintTimer) {
      clearTimeout(this.zenHintTimer);
      this.zenHintTimer = null;
    }
  },

  showZenHint(text) {
    this.clearZenHintTimer();
    this.setData({ zenHintText: text });
    this.zenHintTimer = setTimeout(() => {
      this.setData({ zenHintText: '' });
      this.zenHintTimer = null;
    }, 2000);
  },

  startZenPhase(phase) {
    if (!this.data.zenActive) return;
    this.clearZenPhaseTimer();
    this.zenPhase = phase;

    if (phase === 'inhale') {
      if (this.data.settings.zenHaptics && !this.zenHapticLeadArmed) this.playZenHaptics(HAPTIC_LEAD_MS);
      this.zenPhaseTimer = setTimeout(() => {
        this.startZenPhase('exhale');
      }, BREATH_PHASE_MS);
      return;
    }

    this.clearZenHapticTimers();
    this.zenHapticLeadArmed = false;
    this.scheduleZenHapticLead();
    this.zenPhaseTimer = setTimeout(() => {
      this.startZenPhase('inhale');
    }, BREATH_PHASE_MS);
  },

  scheduleZenHapticLead() {
    if (!this.data.zenActive || this.zenPhase !== 'exhale' || !this.data.settings.zenHaptics) return;
    this.clearZenHapticTimers();
    this.zenHapticLeadArmed = true;
    this.zenHapticTimers = HAPTIC_PATTERNS.inhale.map((cue) => (
      setTimeout(() => {
        if (this.data.zenActive && this.zenHapticLeadArmed) vibrateShort(cue.type);
      }, BREATH_PHASE_MS + cue.at - HAPTIC_LEAD_MS)
    ));
  },

  playZenHaptics(leadMs = 0) {
    this.clearZenHapticTimers();
    this.zenHapticTimers = HAPTIC_PATTERNS.inhale.map((cue) => (
      setTimeout(() => {
        if (this.data.zenActive && this.zenPhase === 'inhale') vibrateShort(cue.type);
      }, Math.max(0, cue.at - leadMs))
    ));
  },

  playZenSound() {
    this.stopZenAudio();
    const audio = this.startZenAudioTrack(ZEN_AUDIO_VOLUME);
    if (!audio) return;
    this.zenAudioCurrent = audio;
    this.scheduleZenAudioCrossfade(audio);
  },

  stopZenAudio() {
    this.clearZenAudioTimers();
    const players = this.zenAudioPlayers || [];
    players.forEach((audio) => this.destroyZenAudio(audio));
    this.zenAudioPlayers = [];
    this.zenAudioCurrent = null;
  },

  startZenAudioTrack(volume) {
    const audio = createZenAudio(ZEN_AUDIO_SOURCE, volume);
    if (!audio) return null;

    audio.__zenCrossfadeStarted = false;
    this.zenAudioPlayers = this.zenAudioPlayers || [];
    this.zenAudioPlayers.push(audio);

    if (audio.onTimeUpdate) {
      audio.onTimeUpdate(() => {
        if (audio !== this.zenAudioCurrent || audio.__zenCrossfadeStarted) return;
        const duration = Number(audio.duration) || ZEN_AUDIO_FALLBACK_DURATION_MS / 1000;
        if (duration && audio.currentTime >= duration - ZEN_AUDIO_CROSSFADE_MS / 1000) {
          this.crossfadeZenAudio();
        }
      });
    }

    if (audio.onEnded) {
      audio.onEnded(() => {
        if (audio !== this.zenAudioCurrent) return;
        if (!this.data.zenActive || !this.data.settings.zenSound) return;
        this.crossfadeZenAudio(true);
      });
    }

    try {
      if (audio.seek) audio.seek(0);
      audio.play();
    } catch (error) {
      console.warn('Zen cue playback failed:', error);
    }
    return audio;
  },

  scheduleZenAudioCrossfade(audio) {
    this.clearZenAudioNextTimer();
    this.zenAudioNextTimer = setTimeout(() => {
      if (audio === this.zenAudioCurrent) this.crossfadeZenAudio();
    }, Math.max(0, ZEN_AUDIO_FALLBACK_DURATION_MS - ZEN_AUDIO_CROSSFADE_MS));
  },

  crossfadeZenAudio(immediate = false) {
    if (!this.data.zenActive || !this.data.settings.zenSound) return;

    const previous = this.zenAudioCurrent;
    if (previous && previous.__zenCrossfadeStarted) return;
    if (previous) previous.__zenCrossfadeStarted = true;

    const next = this.startZenAudioTrack(immediate ? ZEN_AUDIO_VOLUME : 0);
    if (!next) return;

    this.zenAudioCurrent = next;
    this.scheduleZenAudioCrossfade(next);

    if (immediate || !previous) {
      this.destroyZenAudio(previous);
      setAudioVolume(next, ZEN_AUDIO_VOLUME);
      return;
    }

    this.fadeZenAudioPair(previous, next);
  },

  fadeZenAudioPair(previous, next) {
    this.clearZenAudioFadeTimer();
    const steps = Math.max(1, Math.ceil(ZEN_AUDIO_CROSSFADE_MS / ZEN_AUDIO_FADE_STEP_MS));
    let step = 0;

    this.zenAudioFadeTimer = setInterval(() => {
      step += 1;
      const progress = Math.min(1, step / steps);
      setAudioVolume(previous, ZEN_AUDIO_VOLUME * (1 - progress));
      setAudioVolume(next, ZEN_AUDIO_VOLUME * progress);

      if (progress < 1) return;
      this.clearZenAudioFadeTimer();
      this.destroyZenAudio(previous);
    }, ZEN_AUDIO_FADE_STEP_MS);
  },

  clearZenAudioTimers() {
    this.clearZenAudioNextTimer();
    this.clearZenAudioFadeTimer();
  },

  clearZenAudioNextTimer() {
    if (this.zenAudioNextTimer) {
      clearTimeout(this.zenAudioNextTimer);
      this.zenAudioNextTimer = null;
    }
  },

  clearZenAudioFadeTimer() {
    if (this.zenAudioFadeTimer) {
      clearInterval(this.zenAudioFadeTimer);
      this.zenAudioFadeTimer = null;
    }
  },

  destroyZenAudio(audio) {
    if (!audio) return;
    try {
      audio.stop();
      audio.destroy();
    } catch (error) {
      console.warn('Zen cue audio cleanup failed:', error);
    }
    this.zenAudioPlayers = (this.zenAudioPlayers || []).filter((item) => item !== audio);
  },

  onVideoEnded() {
    // Keep the user's current background unless they explicitly switch videos.
  },

  openSettings() {
    wx.navigateTo({
      url: '/pages/settings/settings',
    });
  },
});
