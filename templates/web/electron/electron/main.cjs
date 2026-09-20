// The Electron main process: one window, loading the SvelteKit build
// from disk in a packaged app and the dev server while developing.
const { app, BrowserWindow, shell } = require('electron');
const path = require('node:path');

const isDev = !app.isPackaged;

function createWindow() {
  const window = new BrowserWindow({
    width: 1200,
    height: 800,
    show: false,
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      // The renderer is a web page and is treated as one: no node in it,
      // and anything it needs from the system goes through the preload.
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  });

  // Shown once it has something to draw, so the window does not flash
  // white on a slow first paint.
  window.once('ready-to-show', () => window.show());

  // A link to somewhere else opens in the browser, not in the app.
  window.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });

  if (isDev) {
    window.loadURL('http://localhost:5173');
    window.webContents.openDevTools({ mode: 'detach' });
  } else {
    window.loadFile(path.join(__dirname, '..', 'build', 'index.html'));
  }
}

app.whenReady().then(() => {
  createWindow();
  // macOS keeps the app running with no windows; clicking the dock icon
  // is what asks for one back.
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

// Everywhere but macOS, closing the last window closes the app.
app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
