const {
  resetZenCuesForEntry,
  resetZenSoundForForeground,
} = require('./utils/storage.js');

App({
  globalData: {
    buildTarget: 'wechat-miniprogram',
    resetAmbientSoundOnPageShow: false,
    backgroundSessionActive: false,
  },

  onShow() {
    const wasBackgroundSessionActive = !!this.globalData.backgroundSessionActive;
    this.globalData.backgroundSessionActive = false;
    if (!wasBackgroundSessionActive) {
      resetZenCuesForEntry();
      resetZenSoundForForeground();
    }
    const pages = typeof getCurrentPages === 'function' ? getCurrentPages() : [];
    const currentPage = pages[pages.length - 1];
    if (currentPage && typeof currentPage.handleAppForeground === 'function') {
      currentPage.handleAppForeground(wasBackgroundSessionActive);
    }
  },

  onHide(options = {}) {
    const pages = typeof getCurrentPages === 'function' ? getCurrentPages() : [];
    const currentPage = pages[pages.length - 1];
    const hideReason = Number(options.reason);
    const isUserExit = Number.isFinite(hideReason) && hideReason === 0;
    const backgroundSessionActive = !isUserExit && !!(
      currentPage
      && typeof currentPage.handleAppBackground === 'function'
      && currentPage.handleAppBackground()
    );
    this.globalData.backgroundSessionActive = backgroundSessionActive;
    this.globalData.resetAmbientSoundOnPageShow = !backgroundSessionActive;
    if (isUserExit) {
      resetZenCuesForEntry();
      resetZenSoundForForeground();
      if (currentPage && typeof currentPage.handleAppExit === 'function') {
        currentPage.handleAppExit();
      }
    }
    if (!backgroundSessionActive && currentPage && typeof currentPage.resetAmbientSound === 'function') {
      currentPage.resetAmbientSound();
    }
  },
});
