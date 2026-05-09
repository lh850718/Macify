const { getSettings } = require('../../utils/storage.js');
const { pickQuote } = require('../../utils/quotes.js');
const { pickVideo } = require('../../utils/videos.js');
const { getForecast, describeWeather } = require('../../utils/weather.js');

function pad(value) {
  return String(value).padStart(2, '0');
}

function formatDate(date) {
  const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  return `${weekdays[date.getDay()]} ${date.getFullYear()}.${pad(date.getMonth() + 1)}.${pad(date.getDate())}`;
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
    videoReady: false,
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
    this.setData(
      {
        settings,
      },
      () => {
        if (!this.data.currentVideo) this.nextVideo();
        if (!this.data.currentQuote) this.nextQuote();
        this.loadWeather();
      },
    );
  },

  nextVideo() {
    const settings = this.data.settings && this.data.settings.city ? this.data.settings : getSettings();
    const currentId = this.data.currentVideo && this.data.currentVideo.id;
    const next = pickVideo(settings, currentId);
    this.setData({
      currentVideo: next,
      videoReady: false,
      videoError: '',
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
        });
      })
      .catch((error) => {
        console.warn('Weather load failed:', error);
        this.setData({
          forecast: null,
          weatherLabel: '',
        });
      });
  },

  onVideoEnded() {
    this.nextVideo();
  },

  onVideoPlay() {
    this.setData({
      videoReady: true,
    });
  },

  onVideoError(error) {
    console.warn('Video load failed:', error);
    this.setData({
      videoError: '视频加载失败，已切换下一条',
    });
    setTimeout(() => this.nextVideo(), 700);
  },

  openSettings() {
    wx.navigateTo({
      url: '/pages/settings/settings',
    });
  },
});
