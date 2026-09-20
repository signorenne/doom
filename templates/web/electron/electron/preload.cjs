// The only bridge between the page and the system. Everything the
// renderer may do is named here, one function at a time; it has no
// require and no node of its own.
const { contextBridge } = require('electron');

contextBridge.exposeInMainWorld('app', {
  platform: process.platform,
  versions: {
    electron: process.versions.electron,
    node: process.versions.node,
    chrome: process.versions.chrome
  }
});
