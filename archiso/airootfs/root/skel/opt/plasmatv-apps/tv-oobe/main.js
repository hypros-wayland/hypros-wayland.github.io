// PlasmaTV OOBE — a simple kiosk-style first-boot wizard.
// Runs once (gated by /etc/plasmatv-first-boot, see tv-oobe.service),
// then deletes the marker file so it won't run again.
const { app, BrowserWindow, ipcMain } = require('electron');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

const MARKER = '/etc/plasmatv-first-boot';

function createWindow() {
  const win = new BrowserWindow({
    fullscreen: true,
    frame: false,
    autoHideMenuBar: true,
    backgroundColor: '#0f0f14',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
    },
  });
  win.loadFile('index.html');
}

// ---------------------------------------------------------------------------
// Language / locale
// ---------------------------------------------------------------------------
ipcMain.handle('locale:set', (_evt, localeTag) => new Promise((resolve) => {
  // e.g. localeTag = "en_US.UTF-8"
  exec(`localectl set-locale LANG=${localeTag}`, (err) => resolve(!err));
}));

// ---------------------------------------------------------------------------
// Timezone
// ---------------------------------------------------------------------------
ipcMain.handle('timezone:set', (_evt, tz) => new Promise((resolve) => {
  // e.g. tz = "America/Sao_Paulo"
  exec(`timedatectl set-timezone ${tz}`, (err) => resolve(!err));
}));

// ---------------------------------------------------------------------------
// Wi-Fi
// ---------------------------------------------------------------------------
ipcMain.handle('wifi:scan', () => new Promise((resolve) => {
  exec('nmcli -t -f SSID,SIGNAL dev wifi list', (err, stdout) => {
    if (err) return resolve([]);
    const nets = stdout.split('\n').filter(Boolean).map((l) => {
      const [ssid, signal] = l.split(':');
      return { ssid, signal };
    });
    resolve(nets);
  });
}));

ipcMain.handle('wifi:connect', (_evt, { ssid, password }) => new Promise((resolve) => {
  const cmd = `nmcli dev wifi connect ${JSON.stringify(ssid)} password ${JSON.stringify(password)}`;
  exec(cmd, (err) => resolve(!err));
}));

// ---------------------------------------------------------------------------
// Appearance (Plasma look-and-feel package)
// ---------------------------------------------------------------------------
ipcMain.handle('theme:set', (_evt, lookAndFeelId) => new Promise((resolve) => {
  // e.g. "org.kde.breezedark.desktop" or "org.kde.breeze.desktop"
  exec(`lookandfeeltool -a ${lookAndFeelId}`, (err) => resolve(!err));
}));

// ---------------------------------------------------------------------------
// Finish
// ---------------------------------------------------------------------------
ipcMain.handle('oobe:finish', () => {
  try { fs.unlinkSync(MARKER); } catch (_e) { /* already gone */ }
  app.quit();
});

app.whenReady().then(createWindow);
