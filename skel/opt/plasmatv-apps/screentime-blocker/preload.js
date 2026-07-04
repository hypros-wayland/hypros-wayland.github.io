const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('plasmatv', {
  powerOff: () => ipcRenderer.invoke('power:off'),
});
