export const DEFAULTS = Object.freeze({
  userLanguage: 'auto',
  city: 'Beijing',
  showTime: true,
  hourSystem: '12',
  showWeather: false,
  showMotto: true,
  showTopSites: false,
  showZenMode: true,
  videoSourceUrl: 'http://localhost:18000/videos/',
  refreshButton: true,
  tempUnit: 'celsius',
  authorInfo: true,
  videoSrc: 'apple',
  reverseProxy: true,
  showVideoMetadata: true,
  translateMotto: false,
  zenMusic: true,
  zenBreathingPattern: 'off', // 'off' | 'coherent' | 'box' | '478'
  zenReminderEnabled: false,
  zenReminderMinutes: 60,
  zenAutoExitEnabled: false,
  zenAutoExitMinutes: 15,
});

export const KNOWN_KEYS = Object.freeze(Object.keys(DEFAULTS));
