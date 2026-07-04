// PlasmaTV "Max" kiosk wrapper — a frameless, chromeless Electron
// window pointed at https://www.max.com, styled to feel like a native TV app.
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
  win.loadURL('https://www.max.com');

  // Esc backs out to the Bigscreen shell instead of trapping the user.
  globalShortcut.register('Escape', () => {
    win.close();
  });
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  app.quit();
});
