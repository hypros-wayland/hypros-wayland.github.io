const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('plasmatv', {
  setLocale: (localeTag) => ipcRenderer.invoke('locale:set', localeTag),
  setTimezone: (tz) => ipcRenderer.invoke('timezone:set', tz),
  scanWifi: () => ipcRenderer.invoke('wifi:scan'),
  connectWifi: (ssid, password) => ipcRenderer.invoke('wifi:connect', { ssid, password }),
  setTheme: (lookAndFeelId) => ipcRenderer.invoke('theme:set', lookAndFeelId),
  finish: () => ipcRenderer.invoke('oobe:finish'),
});
