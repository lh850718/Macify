const {
  resetZenCuesForEntry,
  resetZenSoundForForeground,
} = require('./utils/storage.js');

App({
  globalData: {
    buildTarget: 'wechat-miniprogram',
    resetAmbientSoundOnPageShow: false,
  },

  onShow() {
    resetZenCuesForEntry();
    resetZenSoundForForeground();
  },

  onHide() {
    this.globalData.resetAmbientSoundOnPageShow = true;
    const pages = typeof getCurrentPages === 'function' ? getCurrentPages() : [];
    const currentPage = pages[pages.length - 1];
    if (currentPage && typeof currentPage.resetAmbientSound === 'function') {
      currentPage.resetAmbientSound();
    }
  },
});
