const { contextBridge } = require('electron');

contextBridge.exposeInMainWorld('electron', {
  version: process.version
});
