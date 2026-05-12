const { resetZenCuesForEntry } = require('./utils/storage.js');

App({
  globalData: {
    buildTarget: 'wechat-miniprogram',
  },

  onShow() {
    resetZenCuesForEntry();
  },
});
