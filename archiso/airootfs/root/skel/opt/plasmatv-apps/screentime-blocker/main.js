// PlasmaTV Screen Time Blocker — launched by plasmatv-timelimit-daemon
// once a child's daily limit is hit. Deliberately hard to get rid of:
// no frame, always on top, kiosk mode, and its own close handler is
// blocked. The only escape hatch is the Power Off button.
const { app, BrowserWindow, globalShortcut } = require('electron');
const { exec } = require('child_process');

let win;

function createWindow() {
  win = new BrowserWindow({
    fullscreen: true,
    frame: false,
    alwaysOnTop: true,
    kiosk: true,
    closable: false,
    autoHideMenuBar: true,
    backgroundColor: '#0f0f14',
    webPreferences: {
      preload: `${__dirname}/preload.js`,
      contextIsolation: true,
    },
  });

  win.setAlwaysOnTop(true, 'screen-saver');
  win.loadFile('index.html');

  // Block the usual ways out. This isn't a perfect sandbox (nothing on a
  // general-purpose Linux desktop truly is), but it removes the easy
  // escapes for a kid without a keyboard shortcuts cheat sheet.
  win.on('close', (e) => e.preventDefault());
  ['Escape', 'Alt+F4', 'Alt+Tab', 'CommandOrControl+Q', 'CommandOrControl+W'].forEach((accel) => {
    globalShortcut.register(accel, () => {});
  });
}

app.on('will-quit', () => globalShortcut.unregisterAll());

app.whenReady().then(createWindow);

const { ipcMain } = require('electron');
ipcMain.handle('power:off', () => new Promise((resolve) => {
  exec('systemctl poweroff', (err) => resolve(!err));
}));
