// PlasmaTV Child Manager — adult-only. Refuses outright if launched from
// a child-user-* session (belt-and-suspenders on top of it not being
// shipped/shown for those accounts, and on top of sudoers not granting
// child accounts these commands at all).
const { app, BrowserWindow, ipcMain } = require('electron');
const { exec } = require('child_process');
const fs = require('fs');
const os = require('os');

const PUBLIC_USERS = '/etc/plasmatv/users-public.json';
const isChildSession = /^child-user-/.test(os.userInfo().username);

function createWindow() {
  const win = new BrowserWindow({
    width: 900,
    height: 650,
    frame: true,
    autoHideMenuBar: true,
    backgroundColor: '#0f0f14',
    webPreferences: {
      preload: `${__dirname}/preload.js`,
      contextIsolation: true,
    },
  });
  win.loadFile(isChildSession ? 'refused.html' : 'index.html');
}

ipcMain.handle('users:list', () => {
  try {
    return JSON.parse(fs.readFileSync(PUBLIC_USERS, 'utf8'));
  } catch (_e) {
    return {};
  }
});

function guarded(handler) {
  return (...args) => (isChildSession ? Promise.resolve(false) : handler(...args));
}

ipcMain.handle('child:create', guarded((_evt, { slot, name, limit }) => new Promise((resolve) => {
  const cmd = `sudo /usr/local/sbin/plasmatv-manage-child-user create ${JSON.stringify(slot)} ${JSON.stringify(name)} ${JSON.stringify(String(limit))}`;
  exec(cmd, (err) => resolve(!err));
})));

ipcMain.handle('child:delete', guarded((_evt, slot) => new Promise((resolve) => {
  exec(`sudo /usr/local/sbin/plasmatv-manage-child-user delete ${JSON.stringify(slot)}`, (err) => resolve(!err));
})));

ipcMain.handle('child:setName', guarded((_evt, { slot, name }) => new Promise((resolve) => {
  exec(`sudo /usr/local/sbin/plasmatv-manage-child-user set-name ${JSON.stringify(slot)} ${JSON.stringify(name)}`, (err) => resolve(!err));
})));

ipcMain.handle('child:setLimit', guarded((_evt, { slot, minutes }) => new Promise((resolve) => {
  exec(`sudo /usr/local/sbin/plasmatv-manage-child-user set-limit ${JSON.stringify(slot)} ${JSON.stringify(String(minutes))}`, (err) => resolve(!err));
})));

ipcMain.handle('pin:set', guarded((_evt, { user, pin }) => new Promise((resolve) => {
  const safePin = String(pin).replace(/[^0-9]/g, '');
  exec(`sudo /usr/local/sbin/plasmatv-set-pin ${JSON.stringify(user)} ${JSON.stringify(safePin)}`, (err) => resolve(!err));
})));

ipcMain.handle('pin:clear', guarded((_evt, user) => new Promise((resolve) => {
  exec(`sudo /usr/local/sbin/plasmatv-clear-pin ${JSON.stringify(user)}`, (err) => resolve(!err));
})));

app.whenReady().then(createWindow);
