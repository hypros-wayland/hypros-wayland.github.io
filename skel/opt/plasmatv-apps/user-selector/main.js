// PlasmaTV User Selector — runs as the entire session for selector-user
// (see /usr/share/wayland-sessions/plasmatv-selector.desktop). Shows the
// TV User plus any configured child-user-* accounts, checks a PIN if one
// is set, then hands off to plasmatv-login-as via sudo (scoped in
// /etc/sudoers.d/plasmatv-selector — this process has NO other root
// access).
const { app, BrowserWindow, ipcMain } = require('electron');
const { exec } = require('child_process');
const fs = require('fs');

const PUBLIC_USERS = '/etc/plasmatv/users-public.json';

function createWindow() {
  const win = new BrowserWindow({
    fullscreen: true,
    frame: false,
    autoHideMenuBar: true,
    backgroundColor: '#0f0f14',
    webPreferences: {
      preload: `${__dirname}/preload.js`,
      contextIsolation: true,
    },
  });
  win.loadFile('index.html');
}

ipcMain.handle('users:list', () => {
  try {
    const raw = fs.readFileSync(PUBLIC_USERS, 'utf8');
    return JSON.parse(raw);
  } catch (_e) {
    return {};
  }
});

ipcMain.handle('login:verifyPin', (_evt, { user, pin }) => new Promise((resolve) => {
  const safePin = String(pin).replace(/[^0-9]/g, '');
  exec(`sudo /usr/local/sbin/plasmatv-verify-pin ${JSON.stringify(user)} ${JSON.stringify(safePin)}`,
    (err) => resolve(!err));
}));

ipcMain.handle('login:go', (_evt, user) => new Promise((resolve) => {
  exec(`sudo /usr/local/sbin/plasmatv-login-as ${JSON.stringify(user)}`, (err) => resolve(!err));
}));

app.whenReady().then(createWindow);
