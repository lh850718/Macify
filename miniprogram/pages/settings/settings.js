const { getSettings, saveSettings } = require('../../utils/storage.js');
const {
  VIDEO_LIBRARY_OPTIONS,
  activeVideoLibrary,
  categoryLabel,
  categoryOptionsForLibrary,
} = require('../../utils/videos.js');

function storedVideoLibrary(settings) {
  return settings.videoLibrary === 'premiumFreeAerial'
    ? 'premiumFreeAerial'
    : 'apple';
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

function viewDataForSettings(settings) {
  const library = activeVideoLibrary(settings);
  const storedLibrary = storedVideoLibrary(settings);
  return {
    settings,
    categoryOptions: categoryOptionsFor(settings.shuffleScope, library),
    categoryIndex: categoryIndexFor(settings.shuffleScope, library),
    categoryText: categoryLabel(settings.shuffleScope, library),
    tempIsCelsius: settings.tempUnit === 'celsius',
    tempIsFahrenheit: settings.tempUnit === 'fahrenheit',
    videoSourceIsApple1080: settings.videoSource === 'apple1080',
    videoSourceIsLite: settings.videoSource === 'lite',
    videoLibraryOptions: VIDEO_LIBRARY_OPTIONS.map((item) => ({
      ...item,
      selected: item.value === storedLibrary,
    })),
    videoLibraryIsApple: storedLibrary === 'apple',
    videoLibraryIsPremiumFreeAerial: storedLibrary === 'premiumFreeAerial',
  };
}

function formValue(values, settings, key) {
  if (values && Object.prototype.hasOwnProperty.call(values, key)) {
    return values[key];
  }
  return settings[key] || '';
}

Page({
  data: {
    settings: {},
    categoryOptions: categoryOptionsFor('all'),
    categoryIndex: 0,
    categoryText: '',
    tempIsCelsius: true,
    tempIsFahrenheit: false,
    videoSourceIsApple1080: true,
    videoSourceIsLite: false,
    videoLibraryOptions: VIDEO_LIBRARY_OPTIONS,
    videoLibraryIsApple: true,
    videoLibraryIsPremiumFreeAerial: false,
  },

  onLoad() {
    this.loadSettings();
  },

  onShow() {
    this.loadSettings();
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

  draftInputPatch(values) {
    const settings = this.data.settings || {};
    return {
      city: String(formValue(values, settings, 'city')).trim() || 'Shanghai',
      proxyBase: String(formValue(values, settings, 'proxyBase')).trim(),
      liteVideoBase: String(formValue(values, settings, 'liteVideoBase')).trim(),
      premiumFreeAerialVideoBase: String(formValue(values, settings, 'premiumFreeAerialVideoBase')).trim(),
    };
  },

  saveAndBack(event) {
    this.updateSettings(this.draftInputPatch(event.detail.value));
    wx.navigateBack({
      delta: 1,
      fail: () => {
        wx.redirectTo({
          url: '/pages/index/index',
        });
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

  onPremiumBaseInput(event) {
    this.setData({
      'settings.premiumFreeAerialVideoBase': event.detail.value,
    });
  },

  onPremiumBaseBlur(event) {
    this.updateSettings({
      premiumFreeAerialVideoBase: event.detail.value.trim(),
    });
  },

  onVideoSourceChange(event) {
    const videoSource = event.detail.value;
    const patch = {
      videoSource: event.detail.value,
    };
    if (videoSource === 'apple1080') {
      patch.videoLibrary = 'apple';
      patch.shuffleScope = 'all';
    }
    this.updateSettings(patch);
  },

  onVideoLibraryChange(event) {
    const videoLibrary = event.detail.value === 'premiumFreeAerial' ? 'premiumFreeAerial' : 'apple';
    const patch = {
      videoLibrary,
      videoSource: 'lite',
    };
    if (videoLibrary !== this.data.settings.videoLibrary) {
      patch.shuffleScope = 'all';
    }
    this.updateSettings(patch);
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
});
