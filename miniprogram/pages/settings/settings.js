const { getSettings, saveSettings, resetSettings } = require('../../utils/storage.js');
const { CATEGORY_OPTIONS, categoryLabel } = require('../../utils/videos.js');

function categoryIndexFor(value) {
  const index = CATEGORY_OPTIONS.findIndex((item) => item.value === value);
  return index >= 0 ? index : 0;
}

Page({
  data: {
    settings: {},
    categoryOptions: CATEGORY_OPTIONS,
    categoryIndex: 0,
    categoryText: '',
    tempIsCelsius: true,
    tempIsFahrenheit: false,
    videoSourceIsApple: true,
    videoSourceIsLite: false,
  },

  onLoad() {
    this.loadSettings();
  },

  onShow() {
    this.loadSettings();
  },

  loadSettings() {
    const settings = getSettings();
    this.setData({
      settings,
      categoryIndex: categoryIndexFor(settings.shuffleScope),
      categoryText: categoryLabel(settings.shuffleScope),
      tempIsCelsius: settings.tempUnit === 'celsius',
      tempIsFahrenheit: settings.tempUnit === 'fahrenheit',
      videoSourceIsApple: settings.videoSource !== 'lite',
      videoSourceIsLite: settings.videoSource === 'lite',
    });
  },

  updateSettings(patch) {
    const next = saveSettings({
      ...this.data.settings,
      ...patch,
    });
    this.setData({
      settings: next,
      categoryIndex: categoryIndexFor(next.shuffleScope),
      categoryText: categoryLabel(next.shuffleScope),
      tempIsCelsius: next.tempUnit === 'celsius',
      tempIsFahrenheit: next.tempUnit === 'fahrenheit',
      videoSourceIsApple: next.videoSource !== 'lite',
      videoSourceIsLite: next.videoSource === 'lite',
    });
  },

  onCityInput(event) {
    this.setData({
      'settings.city': event.detail.value,
    });
  },

  onCityBlur(event) {
    this.updateSettings({
      city: event.detail.value.trim() || 'Shanghai',
    });
  },

  onProxyInput(event) {
    this.setData({
      'settings.proxyBase': event.detail.value,
    });
  },

  onProxyBlur(event) {
    this.updateSettings({
      proxyBase: event.detail.value.trim(),
    });
  },

  onLiteBaseInput(event) {
    this.setData({
      'settings.liteVideoBase': event.detail.value,
    });
  },

  onLiteBaseBlur(event) {
    this.updateSettings({
      liteVideoBase: event.detail.value.trim(),
    });
  },

  onVideoSourceChange(event) {
    this.updateSettings({
      videoSource: event.detail.value,
    });
  },

  onTempUnitChange(event) {
    this.updateSettings({
      tempUnit: event.detail.value,
    });
  },

  onCategoryChange(event) {
    const index = Number(event.detail.value);
    const option = CATEGORY_OPTIONS[index] || CATEGORY_OPTIONS[0];
    this.updateSettings({
      shuffleScope: option.value,
    });
  },

  onSwitchChange(event) {
    const key = event.currentTarget.dataset.key;
    this.updateSettings({
      [key]: event.detail.value,
    });
  },

  resetAll() {
    wx.showModal({
      title: '重置设置',
      content: '恢复默认显示和视频来源？',
      confirmText: '重置',
      success: (result) => {
        if (!result.confirm) return;
        const settings = resetSettings();
        this.setData({
          settings,
          categoryIndex: categoryIndexFor(settings.shuffleScope),
          categoryText: categoryLabel(settings.shuffleScope),
          tempIsCelsius: settings.tempUnit === 'celsius',
          tempIsFahrenheit: settings.tempUnit === 'fahrenheit',
          videoSourceIsApple: settings.videoSource !== 'lite',
          videoSourceIsLite: settings.videoSource === 'lite',
        });
      },
    });
  },
});
