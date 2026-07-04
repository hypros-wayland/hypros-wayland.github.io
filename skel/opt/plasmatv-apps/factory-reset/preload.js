const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('plasmatv', {
  factoryReset: () => ipcRenderer.invoke('reset:go'),
});
