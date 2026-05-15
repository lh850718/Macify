const { getSettings, saveSettings } = require('../../utils/storage.js');
const {
  activeVideoLibrary,
  categoryLabel,
  categoryOptionsForLibrary,
} = require('../../utils/videos.js');

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

function viewDataForSettings(settings) {
  const library = activeVideoLibrary(settings);
  return {
    settings,
    categoryOptions: categoryOptionsFor(settings.shuffleScope, library),
    categoryIndex: categoryIndexFor(settings.shuffleScope, library),
    categoryText: categoryLabel(settings.shuffleScope, library),
    tempIsCelsius: settings.tempUnit === 'celsius',
    tempIsFahrenheit: settings.tempUnit === 'fahrenheit',
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
  },

  onLoad() {
    this.loadSettings();
  },

  onShow() {
    this.loadSettings();
  },

  onHide() {
    this.persistDraftSettings();
  },

  onUnload() {
    this.persistDraftSettings();
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
      city: String(settings.city || '').trim() || 'Shanghai',
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
      city: event.detail.value.trim() || 'Shanghai',
    });
  },

  onTempUnitChange(event) {
    this.updateSettings({
      tempUnit: event.detail.value,
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
});
