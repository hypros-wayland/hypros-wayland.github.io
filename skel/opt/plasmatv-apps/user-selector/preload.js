const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('plasmatv', {
  listUsers: () => ipcRenderer.invoke('users:list'),
  verifyPin: (user, pin) => ipcRenderer.invoke('login:verifyPin', { user, pin }),
  login: (user) => ipcRenderer.invoke('login:go', user),
});
