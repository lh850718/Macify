const {
  getSettings,
  isFavoriteVideo,
  setSetting,
  toggleFavoriteVideo,
} = require('../../utils/storage.js');
const { pickQuote } = require('../../utils/quotes.js');
const { shuffledVideoQueue, videoById } = require('../../utils/videos.js');
const { cachedVideoForSettings, cacheVideo } = require('../../utils/video-cache.js');
const { getForecast, describeWeather } = require('../../utils/weather.js');
const {
  AMBIENT_AUDIO_MODES,
  ambientMixFromCustomSettings,
  ambientTrackForVideo,
} = require('../../data/ambient-audio.js');

const BREATH_HAPTIC_BASE_MS = 5000;
const BREATH_SCALE_MIN = 0.45;
const BREATH_SCALE_MAX = 1.2;
const BREATH_HOLD_OPACITY = 0.76;
const BREATH_COMPLETION_MS = 3000;
const BREATH_ENTRY_MS = 760;
const BREATH_PHASE_LABELS = Object.freeze({
  inhale: '吸气',
  holdAfterInhale: '屏息',
  exhale: '呼气',
  holdAfterExhale: '屏息',
});
const HAPTIC_LEAD_MS = 850;
const ZEN_AUDIO_SOURCE = '/assets/breath.mp3';
const ZEN_AUDIO_VOLUME = 0.55;
const ZEN_AUDIO_FALLBACK_DURATION_MS = 63384;
const ZEN_AUDIO_CROSSFADE_MS = 2200;
const ZEN_AUDIO_FADE_STEP_MS = 100;
const AMBIENT_AUDIO_CROSSFADE_MS = 2600;
const AMBIENT_AUDIO_FADE_STEP_MS = 100;
const AMBIENT_AUDIO_STOP_FADE_MS = 900;
const VIDEO_REVEAL_MS = 520;
const VIDEO_LOOP_CROSSFADE_MS = 3000;
const VIDEO_LOOP_PRELOAD_LEAD_MS = 3500;
const SWIPE_MIN_DISTANCE = 54;
const SWIPE_AXIS_RATIO = 1.35;
const SWIPE_MAX_DURATION_MS = 1100;
const VIDEO_ONLY_TAP_GUARD_MS = 450;
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
  const number = Number(value);
  if (!Number.isFinite(number)) return 0;
  return Math.max(0, Math.min(1, number));
}

function setAudioVolume(audio, volume) {
  if (!audio) return;
  try {
    audio.volume = clampVolume(volume);
  } catch (error) {
    console.warn('Audio volume update failed:', error);
  }
}

function createManagedAudio(src, volume, label) {
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
      console.warn(`${label} audio failed:`, error);
    });
  }
  return audio;
}

function createZenAudio(src, volume) {
  return createManagedAudio(src, volume, 'Zen cue');
}

function createAmbientAudio(src, volume) {
  return createManagedAudio(src, volume, 'Ambient');
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

function slotElementId(slot) {
  return slot === 'b' ? 'aerialVideoB' : 'aerialVideoA';
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

function secondsToMs(value) {
  return Math.max(0, Math.round(Number(value) || 0) * 1000);
}

function rhythmPhaseMs(rhythm, phase) {
  if (!rhythm) return 0;
  return secondsToMs(rhythm[phase]);
}

function nextBreathPhase(phase, rhythm) {
  if (phase === 'inhale') {
    return rhythmPhaseMs(rhythm, 'holdAfterInhale') > 0 ? 'holdAfterInhale' : 'exhale';
  }
  if (phase === 'holdAfterInhale') return 'exhale';
  if (phase === 'exhale') {
    return rhythmPhaseMs(rhythm, 'holdAfterExhale') > 0 ? 'holdAfterExhale' : 'inhale';
  }
  return 'inhale';
}

function phaseLeadsIntoInhale(phase, rhythm) {
  return phase === 'holdAfterExhale'
    || (phase === 'exhale' && rhythmPhaseMs(rhythm, 'holdAfterExhale') <= 0);
}

function customBreathIntroText(rhythm) {
  const parts = [];
  if (Number(rhythm.inhale) > 0) parts.push(`吸${rhythm.inhale}秒`);
  if (Number(rhythm.holdAfterInhale) > 0) parts.push(`屏息${rhythm.holdAfterInhale}秒`);
  if (Number(rhythm.exhale) > 0) parts.push(`呼${rhythm.exhale}秒`);
  if (Number(rhythm.holdAfterExhale) > 0) parts.push(`屏息${rhythm.holdAfterExhale}秒`);
  return [
    `本次练习${rhythm.cycles}组`,
    parts.join('->'),
    '可在设置中修改',
  ].join('\n');
}

function windowWidth() {
  try {
    if (wx.getWindowInfo) return wx.getWindowInfo().windowWidth;
    return wx.getSystemInfoSync().windowWidth;
  } catch (error) {
    return 375;
  }
}

function primaryTouchFromEvent(event) {
  return event
    && ((event.changedTouches && event.changedTouches[0]) || (event.touches && event.touches[0]));
}

function touchPointFromEvent(event, fallbackSide) {
  const touch = primaryTouchFromEvent(event);
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
    settings.premiumFreeAerialVideoBase,
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
    videoLoopCrossfading: false,
    videoLoopRevealing: false,
    videoFallbackUsed: false,
    videoOnlyActive: false,
    ambientSoundOn: false,
    ambientTrackAvailable: false,
    ambientTrackLabel: '',
    zenActive: false,
    zenBreathMode: 'default',
    zenPhaseText: '',
    zenHintText: '',
    zenPracticeText: '',
    zenCountdownText: '',
    zenFlowerVisible: true,
    zenFlowerEntering: false,
    zenFlowerBursting: false,
    zenPhaseEntering: false,
    breathFlowerAnimation: null,
    videoError: '',
  },

  onLoad() {
    this.lastVideo = null;
    this.forwardVideo = null;
    this.videoQueue = [];
    this.videoQueueKey = '';
    this.screenTouchStart = null;
    this.videoOnlyEnteredAt = 0;
    this.videoLoopPending = false;
    this.videoLoopIncomingSlot = '';
    this.videoLoopPlaybackStarted = false;
    this.ambientAudioPlayers = [];
    this.ambientAudioChannels = {};
    this.ambientAudioCurrent = null;
    this.ambientAudioTrackId = '';
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
    this.clearVideoLoopState();
    this.clearVideoMessageTimer();
    this.stopAmbientAudio();
    this.stopZenCues();
  },

  onHide() {
    this.resetAmbientSound();
    this.stopZenCues();
  },

  onPullDownRefresh() {
    this.previousVideo();
    this.loadWeather();
    wx.stopPullDownRefresh();
  },

  onScreenTouchStart(event) {
    const touch = primaryTouchFromEvent(event);
    if (!touch) return;
    this.screenTouchStart = {
      x: touch.clientX,
      y: touch.clientY,
      time: Date.now(),
    };
  },

  onScreenTouchEnd(event) {
    const start = this.screenTouchStart;
    this.screenTouchStart = null;

    if (!start || this.data.weatherVisible || this.data.videoIntroVisible) return;

    const touch = primaryTouchFromEvent(event);
    if (!touch) return;

    const deltaX = touch.clientX - start.x;
    const deltaY = touch.clientY - start.y;
    const absX = Math.abs(deltaX);
    const absY = Math.abs(deltaY);
    const elapsed = Date.now() - start.time;

    if (elapsed > SWIPE_MAX_DURATION_MS) return;
    if (absY < SWIPE_MIN_DISTANCE || absY < absX * SWIPE_AXIS_RATIO) return;

    if (deltaY < 0) {
      this.nextVideo({ rememberPrevious: true, preferForward: true });
    } else {
      this.previousVideo();
    }
  },

  onScreenTouchCancel() {
    this.screenTouchStart = null;
  },

  onScreenLongPress() {
    if (this.data.videoOnlyActive || this.data.zenActive || this.data.weatherVisible || this.data.videoIntroVisible) return;
    this.screenTouchStart = null;
    this.videoOnlyEnteredAt = Date.now();
    vibrateShort('medium');
    this.setData({
      videoOnlyActive: true,
      weatherVisible: false,
      videoIntroVisible: false,
      videoError: '',
    });
  },

  onScreenTap() {
    if (!this.data.videoOnlyActive) return;
    if (Date.now() - this.videoOnlyEnteredAt < VIDEO_ONLY_TAP_GUARD_MS) return;
    this.setData({
      videoOnlyActive: false,
    });
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
    const hadCurrentVideo = !!this.data.currentVideo;
    this.playbackSettingsKey = nextPlaybackKey;

    this.setData(
      {
        settings,
      },
      () => {
        if (!hadCurrentVideo) this.restoreCachedOrNextVideo();
        else if (playbackChanged) {
          this.lastVideo = null;
          this.forwardVideo = null;
          this.resetVideoQueue();
          this.nextVideo({ rememberPrevious: false });
        }
        if (!this.data.currentQuote) this.nextQuote();
        this.loadWeather();
        if (hadCurrentVideo && !playbackChanged) this.refreshAmbientAudioState();
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
    if (options.clearPrevious) {
      this.lastVideo = null;
    } else if (options.rememberPrevious && current && next && !sameVideo(current, next)) {
      this.lastVideo = current;
    }
    if (options.clearForward) {
      this.forwardVideo = null;
    }
    this.clearVideoLoopState();
    this.clearVideoMessageTimer();
    const ambientTrack = next ? this.ambientTrackForVideo(next) : null;
    const videoData = {
      currentVideo: next,
      currentVideoIntro: next ? next.description || '' : '',
      currentVideoFavorited: next ? isFavoriteVideo(next) : false,
      ambientTrackAvailable: !!ambientTrack,
      ambientTrackLabel: ambientTrack ? ambientTrack.label : '',
      videoIntroVisible: false,
      videoReady: false,
      videoFallbackUsed: false,
      videoLoopCrossfading: false,
      videoLoopRevealing: false,
      videoError: next && next.warning ? next.warning : '',
    };
    const afterVideoSet = () => {
      if (next && !options.skipCache) this.cacheCurrentVideo(next);
      if (this.data.ambientSoundOn) this.syncAmbientAudioForCurrentVideo();
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
        videoLoopCrossfading: false,
        videoLoopRevealing: false,
      }, () => this.resetAmbientSound());
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
      videoLoopCrossfading: false,
      videoLoopRevealing: false,
    }, afterVideoSet);
  },

  clearVideoTransitionTimer() {
    if (this.videoTransitionTimer) {
      clearTimeout(this.videoTransitionTimer);
      this.videoTransitionTimer = null;
    }
  },

  clearVideoLoopState() {
    this.videoLoopPending = false;
    this.videoLoopIncomingSlot = '';
    this.videoLoopPlaybackStarted = false;
  },

  videoContextForSlot(slot) {
    if (!wx.createVideoContext) return null;
    try {
      return wx.createVideoContext(slotElementId(slot), this);
    } catch (error) {
      console.warn('Video context create failed:', error);
      return null;
    }
  },

  playVideoSlot(slot) {
    const context = this.videoContextForSlot(slot);
    if (!context || !context.play) return;
    try {
      if (context.seek) context.seek(0);
      context.play();
    } catch (error) {
      console.warn('Video play failed:', error);
    }
  },

  activateIncomingVideo(slot, options = {}) {
    const previousSlot = this.data.activeVideoSlot || 'a';
    const isLoopCrossfade = !!options.loopCrossfade;
    const revealMs = isLoopCrossfade ? VIDEO_LOOP_CROSSFADE_MS : VIDEO_REVEAL_MS;
    this.clearVideoTransitionTimer();
    if (isLoopCrossfade) {
      this.videoLoopPlaybackStarted = true;
      this.setData({
        videoReady: true,
        [slotReadyKey(slot)]: true,
        videoTransitionStage: 'idle',
        videoLoopCrossfading: true,
        videoLoopRevealing: true,
      }, () => {
        this.videoTransitionTimer = setTimeout(() => {
          const staleSlot = previousSlot === slot ? otherVideoSlot(slot) : previousSlot;
          this.setData({
            activeVideoSlot: slot,
            incomingVideoSlot: '',
            [slotVideoKey(staleSlot)]: null,
            [slotReadyKey(staleSlot)]: false,
            videoTransitionPoster: '',
            videoTransitionStage: 'idle',
            videoLoopCrossfading: false,
            videoLoopRevealing: false,
          });
          this.clearVideoLoopState();
          this.videoTransitionTimer = null;
        }, revealMs);
      });
      return;
    }

    this.setData({
      activeVideoSlot: slot,
      incomingVideoSlot: '',
      videoReady: true,
      [slotReadyKey(slot)]: true,
      videoTransitionStage: isLoopCrossfade ? 'idle' : 'revealing',
      videoLoopCrossfading: isLoopCrossfade,
      videoLoopRevealing: isLoopCrossfade,
    }, () => {
      this.videoTransitionTimer = setTimeout(() => {
        const staleSlot = previousSlot === slot ? otherVideoSlot(slot) : previousSlot;
        const updates = {
          [slotVideoKey(staleSlot)]: null,
          [slotReadyKey(staleSlot)]: false,
          videoTransitionPoster: '',
          videoTransitionStage: 'idle',
        };
        if (isLoopCrossfade) {
          this.clearVideoLoopState();
          updates.videoLoopCrossfading = false;
          updates.videoLoopRevealing = false;
        }
        this.setData(updates);
        this.videoTransitionTimer = null;
      }, revealMs);
    });
  },

  videoForSlot(slot) {
    return slot === 'b' ? this.data.videoSlotB : this.data.videoSlotA;
  },

  onVideoPlay(event) {
    const slot = event.currentTarget.dataset.slot || 'a';
    if (slot === this.data.incomingVideoSlot) {
      this.activateIncomingVideo(slot, {
        loopCrossfade: this.videoLoopPending && slot === this.videoLoopIncomingSlot,
      });
      return;
    }

    this.setData({
      [slotReadyKey(slot)]: true,
      videoReady: slot === this.data.activeVideoSlot ? true : this.data.videoReady,
    });
  },

  onVideoError(error) {
    console.warn('Video load failed:', error);
    this.clearVideoMessageTimer();
    const slot = error.currentTarget && error.currentTarget.dataset
      ? error.currentTarget.dataset.slot || this.data.activeVideoSlot || 'a'
      : this.data.activeVideoSlot || 'a';
    if (slot !== this.data.activeVideoSlot && slot !== this.data.incomingVideoSlot) return;
    if (this.data.incomingVideoSlot && slot === this.data.activeVideoSlot) return;
    const failedVideo = this.videoForSlot(slot) || this.data.currentVideo;

    if (failedVideo && failedVideo.fallbackUrl && !this.data.videoFallbackUsed) {
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
        videoError: '背景视频加载失败，正在尝试源站回退',
      });
      return;
    }

    this.setData({
      videoError: '视频加载失败，已切换下一条',
    });
    setTimeout(() => this.nextVideo({ rememberPrevious: false }), 700);
  },

  onVideoTimeUpdate(event) {
    const slot = event.currentTarget.dataset.slot || 'a';
    if (slot !== this.data.activeVideoSlot || this.data.incomingVideoSlot) return;
    const detail = event.detail || {};
    const currentTime = Number(detail.currentTime);
    const duration = Number(detail.duration);
    if (!Number.isFinite(currentTime) || !Number.isFinite(duration) || duration <= 3) return;

    const remainingMs = Math.max(0, (duration - currentTime) * 1000);
    if (remainingMs > VIDEO_LOOP_PRELOAD_LEAD_MS) return;
    this.prepareLoopCrossfade(slot);
  },

  prepareLoopCrossfade(activeSlot) {
    if (this.videoLoopPending || this.data.incomingVideoSlot) return;
    if (activeSlot !== this.data.activeVideoSlot) return;
    const current = this.videoForSlot(activeSlot) || this.data.currentVideo;
    if (!current || !current.url) return;

    const incomingSlot = otherVideoSlot(activeSlot);
    this.videoLoopPending = true;
    this.videoLoopIncomingSlot = incomingSlot;
    this.setData({
      [slotVideoKey(incomingSlot)]: {
        ...current,
        loopInstance: Date.now(),
      },
      [slotReadyKey(incomingSlot)]: false,
      incomingVideoSlot: incomingSlot,
      videoLoopCrossfading: true,
      videoLoopRevealing: false,
      videoTransitionPoster: '',
      videoTransitionStage: 'idle',
    }, () => {
      this.playVideoSlot(incomingSlot);
    });
  },

  restoreCachedOrNextVideo() {
    this.nextVideo({ rememberPrevious: false });
  },

  resetVideoQueue() {
    this.videoQueue = [];
    this.videoQueueKey = '';
  },

  ensureVideoQueue(settings, currentId) {
    const key = playbackSettingsKey(settings);
    if (this.videoQueueKey !== key || !Array.isArray(this.videoQueue) || !this.videoQueue.length) {
      this.videoQueue = shuffledVideoQueue(settings, currentId);
      this.videoQueueKey = key;
    }
  },

  takeQueuedVideo(settings, currentId) {
    this.ensureVideoQueue(settings, currentId);
    if (!this.videoQueue.length) return null;

    let next = this.videoQueue.shift();
    if (next && currentId && next.id === currentId && this.videoQueue.length) {
      this.videoQueue.push(next);
      next = this.videoQueue.shift();
    }
    return next || null;
  },

  cachedVersionOf(settings, video) {
    if (!video) return null;
    return cachedVideoForSettings(settings, (candidateSettings, cachedId) => {
      if (cachedId !== video.id) return null;
      return videoById(candidateSettings, cachedId);
    });
  },

  nextVideo(options = {}) {
    this.clearVideoMessageTimer();

    if (options.preferForward && this.forwardVideo) {
      const forward = this.forwardVideo;
      this.setCurrentVideo(forward, {
        rememberPrevious: options.rememberPrevious !== false,
        clearForward: true,
      });
      return;
    }

    this.forwardVideo = null;
    const settings = this.data.settings && this.data.settings.city ? this.data.settings : getSettings();
    const currentId = this.data.currentVideo && this.data.currentVideo.id;
    const queued = this.takeQueuedVideo(settings, currentId);
    const next = this.cachedVersionOf(settings, queued) || queued;
    if (!next) {
      this.setData({
        videoError: settings.shuffleScope === 'favorites'
          ? '还没有收藏视频，请先在左上角介绍里点爱心收藏'
          : '当前播放范围暂无视频',
      });
      return;
    }
    this.setCurrentVideo(next, {
      rememberPrevious: options.rememberPrevious !== false,
    });
  },

  previousVideo() {
    const previous = this.lastVideo;
    if (!previous) {
      this.showVideoMessage('没有上一条视频');
      return;
    }
    const current = this.data.currentVideo;
    this.forwardVideo = current && !sameVideo(current, previous) ? current : null;
    this.setCurrentVideo(previous, { clearPrevious: true });
  },

  clearVideoMessageTimer() {
    if (this.videoMessageTimer) {
      clearTimeout(this.videoMessageTimer);
      this.videoMessageTimer = null;
    }
  },

  showVideoMessage(text, duration = 1500) {
    this.clearVideoMessageTimer();
    this.setData({ videoError: text });
    this.videoMessageTimer = setTimeout(() => {
      this.setData({ videoError: '' });
      this.videoMessageTimer = null;
    }, duration);
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

    const token = `${video.videoLibrary || 'premiumFreeAerial'}:${video.id}:${Date.now()}`;
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
    if (this.data.settings && this.data.settings.shuffleScope === 'favorites') {
      this.resetVideoQueue();
    }
    this.setData({
      currentVideoFavorited: result.favorited,
    });
    wx.showToast({
      title: result.favorited ? FAVORITE_TOAST_TEXT : '已取消收藏',
      icon: 'none',
      duration: result.favorited ? 2600 : 1500,
    });
  },

  ambientTrackForVideo(video) {
    const settings = this.data.settings || getSettings();
    if (settings.ambientAudioMode === AMBIENT_AUDIO_MODES.CUSTOM) {
      return ambientMixFromCustomSettings(settings.customAmbientMix);
    }
    return ambientTrackForVideo(video);
  },

  currentAmbientTrack() {
    return this.ambientTrackForVideo(this.data.currentVideo);
  },

  refreshAmbientAudioState() {
    const track = this.currentAmbientTrack();
    this.setData({
      ambientTrackAvailable: !!track,
      ambientTrackLabel: track ? track.label : '',
    }, () => {
      if (this.data.ambientSoundOn) this.syncAmbientAudioForCurrentVideo();
    });
  },

  toggleAmbientSound() {
    if (this.data.ambientSoundOn) {
      this.setData({ ambientSoundOn: false });
      this.fadeOutAmbientAudio();
      return;
    }

    const track = this.currentAmbientTrack();
    if (!track) {
      wx.showToast({
        title: this.data.settings && this.data.settings.ambientAudioMode === AMBIENT_AUDIO_MODES.CUSTOM
          ? '请在设置里调大混音音量'
          : '当前视频暂无匹配音频',
        icon: 'none',
        duration: 1500,
      });
      return;
    }

    this.setData({
      ambientSoundOn: true,
      ambientTrackAvailable: true,
      ambientTrackLabel: track.label,
    }, () => {
      this.switchAmbientTrack(track);
    });
  },

  resetAmbientSound() {
    this.stopAmbientAudio();
    if (this.data.ambientSoundOn) {
      this.setData({ ambientSoundOn: false });
    }
  },

  syncAmbientAudioForCurrentVideo() {
    if (!this.data.ambientSoundOn) return;
    const track = this.currentAmbientTrack();
    if (!track) {
      this.setData({
        ambientSoundOn: false,
        ambientTrackAvailable: false,
        ambientTrackLabel: '',
      });
      this.fadeOutAmbientAudio();
      return;
    }

    this.setData({
      ambientTrackAvailable: true,
      ambientTrackLabel: track.label,
    });
    this.switchAmbientTrack(track);
  },

  switchAmbientTrack(track) {
    if (this.ambientAudioFadeTimer) {
      clearInterval(this.ambientAudioFadeTimer);
      this.ambientAudioFadeTimer = null;
    }

    const tracks = this.ambientTracksForMix(track);
    if (!tracks.length) return;

    const activeKeys = {};
    tracks.forEach((item) => {
      const key = this.ambientAudioChannelKey(item);
      if (key) activeKeys[key] = true;
    });

    Object.keys(this.ambientAudioChannels || {}).forEach((key) => {
      if (!activeKeys[key]) this.fadeOutAmbientChannel(key);
    });

    tracks.forEach((item) => this.switchAmbientChannelTrack(item));
    this.ambientAudioTrackId = track.id || tracks.map((item) => this.ambientAudioChannelKey(item)).join('+');
  },

  ambientTracksForMix(track) {
    if (!track) return [];
    if (Array.isArray(track.tracks)) return track.tracks.filter((item) => item && item.url);
    return track.url ? [track] : [];
  },

  ambientAudioChannelKey(track) {
    if (!track) return '';
    return track.channelId || track.id || track.file || '';
  },

  ensureAmbientAudioChannel(key) {
    if (!this.ambientAudioChannels) this.ambientAudioChannels = {};
    if (!this.ambientAudioChannels[key]) {
      this.ambientAudioChannels[key] = {
        key,
        current: null,
        nextTimer: null,
        fadeTimer: null,
        targetVolume: 0,
        track: null,
      };
    }
    return this.ambientAudioChannels[key];
  },

  switchAmbientChannelTrack(track) {
    const key = this.ambientAudioChannelKey(track);
    if (!key || !track.url) return;

    const channel = this.ensureAmbientAudioChannel(key);
    const targetVolume = clampVolume(track.volume);
    channel.track = track;
    channel.targetVolume = targetVolume;

    if (channel.current) {
      channel.current.__ambientTrack = track;
      channel.current.__ambientTargetVolume = targetVolume;
      this.destroyAmbientChannelInactivePlayers(key);
      this.scheduleAmbientAudioCrossfade(key, channel.current);
      this.fadeAmbientChannelToVolume(key, targetVolume, AMBIENT_AUDIO_CROSSFADE_MS);
      return;
    }

    const next = this.startAmbientAudioTrack(track, 0, key);
    if (!next) return;

    channel.current = next;
    this.scheduleAmbientAudioCrossfade(key, next);
    this.fadeAmbientChannelToVolume(key, targetVolume, AMBIENT_AUDIO_CROSSFADE_MS);
  },

  startAmbientAudioTrack(track, volume, channelKey) {
    const audio = createAmbientAudio(track.url, volume);
    if (!audio) return null;

    audio.__ambientTrack = track;
    audio.__ambientChannelKey = channelKey;
    audio.__ambientTargetVolume = clampVolume(track.volume);
    audio.__ambientLastVolume = clampVolume(volume);
    audio.__ambientCrossfadeStarted = false;
    this.ambientAudioPlayers = this.ambientAudioPlayers || [];
    this.ambientAudioPlayers.push(audio);

    if (audio.onTimeUpdate) {
      audio.onTimeUpdate(() => {
        const channel = this.ambientAudioChannels && this.ambientAudioChannels[channelKey];
        if (!channel || audio !== channel.current || audio.__ambientCrossfadeStarted) return;
        const duration = Number(audio.duration) || (track.durationMs || 0) / 1000;
        if (duration && audio.currentTime >= duration - AMBIENT_AUDIO_CROSSFADE_MS / 1000) {
          this.crossfadeAmbientAudio(channelKey);
        }
      });
    }

    if (audio.onEnded) {
      audio.onEnded(() => {
        const channel = this.ambientAudioChannels && this.ambientAudioChannels[channelKey];
        if (!channel || audio !== channel.current) return;
        if (!this.data.ambientSoundOn) return;
        this.crossfadeAmbientAudio(channelKey, true);
      });
    }

    try {
      if (audio.seek) audio.seek(0);
      audio.play();
    } catch (error) {
      console.warn('Ambient playback failed:', error);
    }
    return audio;
  },

  scheduleAmbientAudioCrossfade(channelKey, audio) {
    const channel = this.ambientAudioChannels && this.ambientAudioChannels[channelKey];
    if (!channel) return;
    this.clearAmbientChannelNextTimer(channel);
    const track = audio && audio.__ambientTrack;
    if (!track || !track.durationMs) return;
    channel.nextTimer = setTimeout(() => {
      const currentChannel = this.ambientAudioChannels && this.ambientAudioChannels[channelKey];
      if (currentChannel && audio === currentChannel.current) this.crossfadeAmbientAudio(channelKey);
    }, Math.max(0, track.durationMs - AMBIENT_AUDIO_CROSSFADE_MS));
  },

  crossfadeAmbientAudio(channelKey, immediate = false) {
    if (!this.data.ambientSoundOn) return;
    const channel = this.ambientAudioChannels && this.ambientAudioChannels[channelKey];
    if (!channel) return;
    const previous = channel.current;
    const track = channel.track || (previous && previous.__ambientTrack);
    if (!track) return;
    if (previous && previous.__ambientCrossfadeStarted) return;
    if (previous) previous.__ambientCrossfadeStarted = true;

    const next = this.startAmbientAudioTrack(track, immediate ? channel.targetVolume : 0, channelKey);
    if (!next) return;

    channel.current = next;
    this.scheduleAmbientAudioCrossfade(channelKey, next);

    if (immediate || !previous) {
      this.destroyAmbientAudio(previous);
      setAudioVolume(next, channel.targetVolume);
      return;
    }

    this.fadeAmbientAudioPair(
      channelKey,
      previous,
      next,
      previous.__ambientLastVolume == null ? previous.__ambientTargetVolume : previous.__ambientLastVolume,
      channel.targetVolume,
      AMBIENT_AUDIO_CROSSFADE_MS,
    );
  },

  fadeAmbientAudioPair(channelKey, previous, next, previousVolume, nextVolume, durationMs) {
    const channel = this.ambientAudioChannels && this.ambientAudioChannels[channelKey];
    if (!channel) return;
    this.clearAmbientChannelFadeTimer(channel);
    const steps = Math.max(1, Math.ceil(durationMs / AMBIENT_AUDIO_FADE_STEP_MS));
    let step = 0;

    channel.fadeTimer = setInterval(() => {
      step += 1;
      const progress = Math.min(1, step / steps);
      const previousNextVolume = clampVolume(previousVolume * (1 - progress));
      const nextNextVolume = clampVolume(nextVolume * progress);
      if (previous) {
        previous.__ambientLastVolume = previousNextVolume;
        setAudioVolume(previous, previousNextVolume);
      }
      if (next) {
        next.__ambientLastVolume = nextNextVolume;
        setAudioVolume(next, nextNextVolume);
      }

      if (progress < 1) return;
      this.clearAmbientChannelFadeTimer(channel);
      this.destroyAmbientAudio(previous);
      if (next) {
        next.__ambientLastVolume = clampVolume(nextVolume);
        setAudioVolume(next, next.__ambientLastVolume);
      }
    }, AMBIENT_AUDIO_FADE_STEP_MS);
  },

  fadeAmbientChannelToVolume(channelKey, targetVolume, durationMs) {
    const channel = this.ambientAudioChannels && this.ambientAudioChannels[channelKey];
    const audio = channel && channel.current;
    if (!channel || !audio) return;

    const startVolume = audio.__ambientLastVolume == null ? audio.__ambientTargetVolume || 0 : audio.__ambientLastVolume;
    const endVolume = clampVolume(targetVolume);
    audio.__ambientTargetVolume = endVolume;
    if (Math.abs(startVolume - endVolume) < 0.01) {
      audio.__ambientLastVolume = endVolume;
      setAudioVolume(audio, endVolume);
      return;
    }

    this.clearAmbientChannelFadeTimer(channel);
    const steps = Math.max(1, Math.ceil(durationMs / AMBIENT_AUDIO_FADE_STEP_MS));
    let step = 0;

    channel.fadeTimer = setInterval(() => {
      step += 1;
      const progress = Math.min(1, step / steps);
      const nextVolume = clampVolume(startVolume + (endVolume - startVolume) * progress);
      audio.__ambientLastVolume = nextVolume;
      setAudioVolume(audio, nextVolume);

      if (progress < 1) return;
      this.clearAmbientChannelFadeTimer(channel);
      audio.__ambientLastVolume = endVolume;
      setAudioVolume(audio, endVolume);
    }, AMBIENT_AUDIO_FADE_STEP_MS);
  },

  fadeOutAmbientChannel(channelKey) {
    const channel = this.ambientAudioChannels && this.ambientAudioChannels[channelKey];
    if (!channel) return;
    this.clearAmbientChannelNextTimer(channel);
    this.clearAmbientChannelFadeTimer(channel);

    const players = (this.ambientAudioPlayers || []).filter((audio) => audio.__ambientChannelKey === channelKey);
    if (!players.length) {
      delete this.ambientAudioChannels[channelKey];
      return;
    }

    const startVolumes = players.map((audio) => (
      audio.__ambientLastVolume == null ? audio.__ambientTargetVolume || 0 : audio.__ambientLastVolume
    ));
    const steps = Math.max(1, Math.ceil(AMBIENT_AUDIO_STOP_FADE_MS / AMBIENT_AUDIO_FADE_STEP_MS));
    let step = 0;

    channel.fadeTimer = setInterval(() => {
      step += 1;
      const progress = Math.min(1, step / steps);
      players.forEach((audio, index) => {
        const nextVolume = clampVolume(startVolumes[index] * (1 - progress));
        audio.__ambientLastVolume = nextVolume;
        setAudioVolume(audio, nextVolume);
      });

      if (progress < 1) return;
      this.clearAmbientChannelFadeTimer(channel);
      players.forEach((audio) => this.destroyAmbientAudio(audio));
      delete this.ambientAudioChannels[channelKey];
    }, AMBIENT_AUDIO_FADE_STEP_MS);
  },

  destroyAmbientChannelInactivePlayers(channelKey) {
    const channel = this.ambientAudioChannels && this.ambientAudioChannels[channelKey];
    if (!channel) return;
    (this.ambientAudioPlayers || [])
      .filter((audio) => audio.__ambientChannelKey === channelKey && audio !== channel.current)
      .forEach((audio) => this.destroyAmbientAudio(audio));
  },

  fadeOutAmbientAudio() {
    this.clearAmbientAudioNextTimer();
    this.clearAmbientAudioFadeTimer();
    const players = (this.ambientAudioPlayers || []).slice();
    if (!players.length) {
      this.ambientAudioCurrent = null;
      this.ambientAudioChannels = {};
      this.ambientAudioTrackId = '';
      return;
    }
    const startVolumes = players.map((audio) => (
      audio.__ambientLastVolume == null ? audio.__ambientTargetVolume || 0 : audio.__ambientLastVolume
    ));
    const steps = Math.max(1, Math.ceil(AMBIENT_AUDIO_STOP_FADE_MS / AMBIENT_AUDIO_FADE_STEP_MS));
    let step = 0;

    this.ambientAudioFadeTimer = setInterval(() => {
      step += 1;
      const progress = Math.min(1, step / steps);
      players.forEach((audio, index) => {
        const nextVolume = clampVolume(startVolumes[index] * (1 - progress));
        audio.__ambientLastVolume = nextVolume;
        setAudioVolume(audio, nextVolume);
      });

      if (progress < 1) return;
      this.clearAmbientAudioFadeTimer();
      players.forEach((audio) => this.destroyAmbientAudio(audio));
      this.ambientAudioCurrent = null;
      this.ambientAudioChannels = {};
      this.ambientAudioTrackId = '';
    }, AMBIENT_AUDIO_FADE_STEP_MS);
  },

  stopAmbientAudio() {
    this.clearAmbientAudioTimers();
    const players = this.ambientAudioPlayers || [];
    players.forEach((audio) => this.destroyAmbientAudio(audio));
    this.ambientAudioPlayers = [];
    this.ambientAudioChannels = {};
    this.ambientAudioCurrent = null;
    this.ambientAudioTrackId = '';
  },

  clearAmbientAudioTimers() {
    this.clearAmbientAudioNextTimer();
    this.clearAmbientAudioFadeTimer();
  },

  clearAmbientAudioNextTimer() {
    Object.keys(this.ambientAudioChannels || {}).forEach((key) => {
      this.clearAmbientChannelNextTimer(this.ambientAudioChannels[key]);
    });
  },

  clearAmbientAudioFadeTimer() {
    if (this.ambientAudioFadeTimer) {
      clearInterval(this.ambientAudioFadeTimer);
      this.ambientAudioFadeTimer = null;
    }
    Object.keys(this.ambientAudioChannels || {}).forEach((key) => {
      this.clearAmbientChannelFadeTimer(this.ambientAudioChannels[key]);
    });
  },

  clearAmbientChannelNextTimer(channel) {
    if (channel && channel.nextTimer) {
      clearTimeout(channel.nextTimer);
      channel.nextTimer = null;
    }
  },

  clearAmbientChannelFadeTimer(channel) {
    if (channel && channel.fadeTimer) {
      clearInterval(channel.fadeTimer);
      channel.fadeTimer = null;
    }
  },

  destroyAmbientAudio(audio) {
    if (!audio) return;
    try {
      audio.stop();
      audio.destroy();
    } catch (error) {
      console.warn('Ambient audio cleanup failed:', error);
    }
    this.ambientAudioPlayers = (this.ambientAudioPlayers || []).filter((item) => item !== audio);
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
      const rhythm = this.currentBreathRhythm();
      const inhaleMs = rhythmPhaseMs(rhythm, 'inhale');
      if (this.zenPhase === 'inhale') {
        this.playZenHaptics(0, inhaleMs);
      } else if (phaseLeadsIntoInhale(this.zenPhase, rhythm)) {
        this.scheduleZenHapticLead(this.delayToNextInhale(), inhaleMs);
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

  startCustomBreath() {
    if (!this.data.zenActive) return;
    this.clearZenPhaseTimer();
    this.clearZenHapticTimers();
    this.clearZenPracticeTimer();
    this.clearZenCountdownTimers();
    const rhythm = this.data.settings.customBreathRhythm || getSettings().customBreathRhythm;
    this.zenBreathMode = 'custom';
    this.zenCustomCycleIndex = 0;
    this.zenCustomTargetCycles = Math.max(1, Number(rhythm.cycles) || 1);
    this.zenCustomIntroActive = true;
    this.zenHapticLeadArmed = false;
    this.setData({
      zenBreathMode: 'custom',
      zenPhaseText: '',
      zenPracticeText: customBreathIntroText(rhythm),
      zenCountdownText: '3',
      zenFlowerVisible: false,
      zenFlowerEntering: false,
      zenFlowerBursting: false,
      zenPhaseEntering: false,
    });
    this.startCustomBreathCountdown();
  },

  completeCustomBreath(cycles) {
    this.clearZenHapticTimers();
    this.clearZenPracticeTimer();
    this.clearZenCountdownTimers();
    this.zenHapticLeadArmed = false;
    this.zenCustomIntroActive = false;
    this.setData({
      zenBreathMode: 'default',
      zenPhaseText: '',
      zenCountdownText: '',
      zenFlowerEntering: false,
      zenFlowerBursting: true,
      zenPhaseEntering: false,
      zenPracticeText: '本次练习完成，恢复默认呼吸',
    });
    this.playBubblePopHaptic();
    this.runBreathCompletionAnimation(() => {
      this.zenBreathMode = 'default';
      this.zenCustomCycleIndex = 0;
      this.zenCustomTargetCycles = 0;
      this.setData({
        zenBreathMode: 'default',
        zenFlowerVisible: false,
        zenFlowerBursting: false,
      });
      this.resetBreathPose(() => {
        this.setData({
          zenPracticeText: '',
          zenFlowerVisible: true,
          zenFlowerEntering: true,
          zenPhaseText: '吸气',
          zenPhaseEntering: true,
        }, () => {
          this.zenPhaseTimer = setTimeout(() => {
            this.setData({
              zenFlowerEntering: false,
              zenPhaseEntering: false,
            }, () => {
              this.startZenPhase('inhale');
            });
          }, BREATH_ENTRY_MS);
        });
      });
    });
  },

  playBubblePopHaptic() {
    if (!this.data.settings || !this.data.settings.zenHaptics) return;
    vibrateShort('light');
    setTimeout(() => {
      if (this.data.zenActive && this.data.settings && this.data.settings.zenHaptics) {
        vibrateShort('light');
      }
    }, 80);
  },

  startCustomBreathCountdown() {
    this.zenCountdownTimers = [
      setTimeout(() => {
        if (this.data.zenActive && this.zenBreathMode === 'custom') {
          this.setData({ zenCountdownText: '2' });
        }
      }, 1000),
      setTimeout(() => {
        if (this.data.zenActive && this.zenBreathMode === 'custom') {
          this.setData({ zenCountdownText: '1' });
        }
      }, 2000),
      setTimeout(() => {
        this.zenCountdownTimers = [];
        if (!this.data.zenActive || this.zenBreathMode !== 'custom') return;
        this.zenCustomIntroActive = false;
        this.setData({
          zenCountdownText: '',
        });
        this.resetBreathPose(() => {
          this.setData({
            zenFlowerVisible: true,
            zenFlowerEntering: true,
            zenPhaseText: '吸气',
            zenPhaseEntering: true,
          }, () => {
            this.zenPhaseTimer = setTimeout(() => {
              this.setData({
                zenFlowerEntering: false,
                zenPhaseEntering: false,
              }, () => {
                this.startZenPhase('inhale');
              });
            }, BREATH_ENTRY_MS);
          });
        });
      }, 3000),
    ];
  },

  startZenCues() {
    this.clearZenPhaseTimer();
    this.clearZenHapticTimers();
    this.clearZenPracticeTimer();
    this.clearZenCountdownTimers();
    this.zenBreathMode = 'default';
    this.zenCustomCycleIndex = 0;
    this.zenCustomTargetCycles = 0;
    this.zenCustomIntroActive = false;
    this.setData({
      zenBreathMode: 'default',
      zenPhaseText: '',
      zenPracticeText: '',
      zenCountdownText: '',
      zenFlowerVisible: true,
      zenFlowerEntering: false,
      zenFlowerBursting: false,
      zenPhaseEntering: false,
    });
    this.resetBreathPose(() => {
      this.startZenPhase('inhale');
    });
    if (this.data.settings.zenSound) this.playZenSound();
  },

  stopZenCues() {
    this.clearZenPhaseTimer();
    this.clearZenHapticTimers();
    this.clearZenHintTimer();
    this.clearZenPracticeTimer();
    this.clearZenCountdownTimers();
    this.setData({
      zenBreathMode: 'default',
      zenPhaseText: '',
      zenHintText: '',
      zenPracticeText: '',
      zenCountdownText: '',
      zenFlowerVisible: true,
      zenFlowerEntering: false,
      zenFlowerBursting: false,
      zenPhaseEntering: false,
    });
    this.stopZenAudio();
    this.zenPhase = null;
    this.zenBreathMode = 'default';
    this.zenCustomCycleIndex = 0;
    this.zenCustomTargetCycles = 0;
    this.zenCustomIntroActive = false;
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

  clearZenPracticeTimer() {
    if (this.zenPracticeTimer) {
      clearTimeout(this.zenPracticeTimer);
      this.zenPracticeTimer = null;
    }
  },

  clearZenCountdownTimers() {
    if (!this.zenCountdownTimers) {
      this.zenCountdownTimers = [];
      return;
    }
    this.zenCountdownTimers.forEach((timer) => clearTimeout(timer));
    this.zenCountdownTimers = [];
  },

  showZenHint(text) {
    this.clearZenHintTimer();
    this.setData({ zenHintText: text });
    this.zenHintTimer = setTimeout(() => {
      this.setData({ zenHintText: '' });
      this.zenHintTimer = null;
    }, 2000);
  },

  currentBreathRhythm() {
    const settings = this.data.settings && Object.keys(this.data.settings).length
      ? this.data.settings
      : getSettings();
    return this.zenBreathMode === 'custom'
      ? settings.customBreathRhythm
      : settings.defaultBreathRhythm;
  },

  updateCustomBreathProgressText() {
    if (!this.data.zenActive || this.zenBreathMode !== 'custom' || this.zenCustomIntroActive) return;
    const targetCycles = this.zenCustomTargetCycles || Math.max(1, Number(this.currentBreathRhythm().cycles) || 1);
    const completedCycles = Math.max(0, this.zenCustomCycleIndex - 1);
    const remainingCycles = Math.max(1, targetCycles - completedCycles);
    this.setData({
      zenPracticeText: `还剩${remainingCycles}组`,
    });
  },

  delayToNextInhale() {
    const rhythm = this.currentBreathRhythm();
    if (!this.zenPhase || this.zenPhase === 'inhale') return 0;
    if (this.zenPhase === 'holdAfterInhale') {
      return rhythmPhaseMs(rhythm, 'exhale') + rhythmPhaseMs(rhythm, 'holdAfterExhale');
    }
    if (this.zenPhase === 'exhale') {
      return rhythmPhaseMs(rhythm, 'exhale') + rhythmPhaseMs(rhythm, 'holdAfterExhale');
    }
    return rhythmPhaseMs(rhythm, 'holdAfterExhale');
  },

  resetBreathPose(callback) {
    if (!wx.createAnimation) {
      if (callback) callback();
      return;
    }
    const animation = wx.createAnimation({
      duration: 0,
      timingFunction: 'linear',
    });
    animation.scale(BREATH_SCALE_MIN).opacity(1).step();
    this.setData({
      breathFlowerAnimation: animation.export(),
    }, () => {
      if (!callback) return;
      this.zenPhaseTimer = setTimeout(callback, 40);
    });
  },

  runBreathPhaseAnimation(phase, durationMs) {
    if (!wx.createAnimation || durationMs <= 0) return;
    const animation = wx.createAnimation({
      duration: durationMs,
      timingFunction: 'ease-in-out',
    });

    if (phase === 'inhale') {
      animation.scale(BREATH_SCALE_MAX).opacity(1).step();
    } else if (phase === 'exhale') {
      animation.scale(BREATH_SCALE_MIN).opacity(1).step();
    } else {
      const scale = phase === 'holdAfterInhale' ? BREATH_SCALE_MAX : BREATH_SCALE_MIN;
      const firstStepMs = Math.max(1, Math.floor(durationMs / 2));
      animation.scale(scale).opacity(BREATH_HOLD_OPACITY).step({
        duration: firstStepMs,
        timingFunction: 'ease-in-out',
      });
      animation.scale(scale).opacity(1).step({
        duration: Math.max(1, durationMs - firstStepMs),
        timingFunction: 'ease-in-out',
      });
    }

    this.setData({
      breathFlowerAnimation: animation.export(),
    });
  },

  runBreathCompletionAnimation(callback) {
    if (!wx.createAnimation) {
      if (callback) callback();
      return;
    }
    const animation = wx.createAnimation({
      duration: BREATH_COMPLETION_MS,
      timingFunction: 'ease-out',
    });
    animation.scale(2.15).rotate(18).opacity(0).step();
    this.setData({
      breathFlowerAnimation: animation.export(),
    });
    this.zenPhaseTimer = setTimeout(() => {
      if (callback) callback();
    }, BREATH_COMPLETION_MS + 80);
  },

  startZenPhase(phase) {
    if (!this.data.zenActive) return;
    this.clearZenPhaseTimer();
    const rhythm = this.currentBreathRhythm();

    if (phase === 'inhale' && this.zenBreathMode === 'custom') {
      const targetCycles = Math.max(1, Number(rhythm.cycles) || 1);
      if (this.zenCustomCycleIndex >= targetCycles) {
        this.completeCustomBreath(targetCycles);
        return;
      }
      this.zenCustomCycleIndex += 1;
    }

    this.zenPhase = phase;
    const durationMs = rhythmPhaseMs(rhythm, phase);
    const inhaleMs = rhythmPhaseMs(rhythm, 'inhale');
    const nextPhase = nextBreathPhase(phase, rhythm);

    if (phase === 'inhale') {
      if (this.data.settings.zenHaptics && !this.zenHapticLeadArmed) {
        this.playZenHaptics(0, inhaleMs);
      }
      if (this.zenBreathMode === 'custom') this.updateCustomBreathProgressText();
    } else if (phase === 'exhale') {
      this.clearZenHapticTimers();
      this.zenHapticLeadArmed = false;
    }

    if (phaseLeadsIntoInhale(phase, rhythm)) {
      this.scheduleZenHapticLead(durationMs, inhaleMs);
    }

    this.setData({
      zenBreathMode: this.zenBreathMode,
      zenPhaseText: BREATH_PHASE_LABELS[phase] || '',
    });
    this.runBreathPhaseAnimation(phase, durationMs);
    this.zenPhaseTimer = setTimeout(() => {
      if (
        (phase === 'holdAfterInhale' && nextPhase === 'exhale')
        || (phase === 'exhale' && nextPhase === 'holdAfterExhale')
      ) {
        this.playBubblePopHaptic();
      }
      this.startZenPhase(nextPhase);
    }, durationMs);
  },

  scheduleZenHapticLead(delayToInhaleMs, inhaleMs) {
    if (!this.data.zenActive || !this.data.settings.zenHaptics) return;
    this.clearZenHapticTimers();
    this.zenHapticLeadArmed = true;
    const scale = Math.max(0.2, inhaleMs / BREATH_HAPTIC_BASE_MS);
    this.zenHapticTimers = HAPTIC_PATTERNS.inhale.map((cue) => (
      setTimeout(() => {
        if (this.data.zenActive && this.data.settings.zenHaptics && this.zenHapticLeadArmed) {
          vibrateShort(cue.type);
        }
      }, Math.max(0, delayToInhaleMs + cue.at * scale - HAPTIC_LEAD_MS))
    ));
  },

  playZenHaptics(leadMs = 0, inhaleMs = BREATH_HAPTIC_BASE_MS) {
    this.clearZenHapticTimers();
    const scale = Math.max(0.2, inhaleMs / BREATH_HAPTIC_BASE_MS);
    this.zenHapticTimers = HAPTIC_PATTERNS.inhale.map((cue) => (
      setTimeout(() => {
        if (this.data.zenActive && this.data.settings.zenHaptics && this.zenPhase === 'inhale') {
          vibrateShort(cue.type);
        }
      }, Math.max(0, cue.at * scale - leadMs))
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

  onVideoEnded(event) {
    const slot = event && event.currentTarget && event.currentTarget.dataset
      ? event.currentTarget.dataset.slot || 'a'
      : this.data.activeVideoSlot || 'a';
    if (slot !== this.data.activeVideoSlot) return;

    if (this.data.incomingVideoSlot && this.videoLoopPending) {
      if (!this.videoLoopPlaybackStarted) this.playVideoSlot(this.data.incomingVideoSlot);
      return;
    }
    this.prepareLoopCrossfade(slot);
  },

  openSettings() {
    wx.navigateTo({
      url: '/pages/settings/settings',
    });
  },
});
