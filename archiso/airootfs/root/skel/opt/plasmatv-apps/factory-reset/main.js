// PlasmaTV Factory Reset — adult-only, refuses if launched from a
// child-user-* session. This is deliberate: a factory reset would be a
// straightforward loophole around parental controls otherwise.
const { app, BrowserWindow, ipcMain } = require('electron');
const { exec } = require('child_process');
const os = require('os');

const isChildSession = /^child-user-/.test(os.userInfo().username);

function createWindow() {
  const win = new BrowserWindow({
    width: 560,
    height: 360,
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

ipcMain.handle('reset:go', () => {
  if (isChildSession) return Promise.resolve(false);
  return new Promise((resolve) => {
    exec('sudo /usr/local/sbin/plasmatv-factory-reset', (err) => resolve(!err));
  });
});

app.whenReady().then(createWindow);
