const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('plasmatv', {
  listUsers: () => ipcRenderer.invoke('users:list'),
  createChild: (slot, name, limit) => ipcRenderer.invoke('child:create', { slot, name, limit }),
  deleteChild: (slot) => ipcRenderer.invoke('child:delete', slot),
  setChildName: (slot, name) => ipcRenderer.invoke('child:setName', { slot, name }),
  setChildLimit: (slot, minutes) => ipcRenderer.invoke('child:setLimit', { slot, minutes }),
  setPin: (user, pin) => ipcRenderer.invoke('pin:set', { user, pin }),
  clearPin: (user) => ipcRenderer.invoke('pin:clear', user),
});
