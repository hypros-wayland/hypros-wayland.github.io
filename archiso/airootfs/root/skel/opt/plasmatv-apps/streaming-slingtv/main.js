// PlasmaTV "Sling TV" kiosk wrapper — a frameless, chromeless Electron
// window pointed at https://watch.sling.com, styled to feel like a native TV app.
const { app, BrowserWindow, globalShortcut } = require('electron');

function createWindow() {
  const win = new BrowserWindow({
    fullscreen: true,
    frame: false,          // no titlebar
    autoHideMenuBar: true,
    backgroundColor: '#000000',
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  win.setMenuBarVisibility(false);
  win.loadURL('https://watch.sling.com');

  // Esc backs out to the Bigscreen shell instead of trapping the user.
  globalShortcut.register('Escape', () => {
    win.close();
  });
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  app.quit();
});
