const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const config = require('../config');
const { getDb, getSetting } = require('../db/client');

function addSoundsFromDir(files, dir, prefix) {
  if (!fs.existsSync(dir)) {
    return;
  }

  for (const name of fs.readdirSync(dir)) {
    const lower = name.toLowerCase();
    if (!lower.endsWith('.wav') && !lower.endsWith('.mp3') && !lower.endsWith('.ogg')) {
      continue;
    }
    files.set(prefix + name, path.join(dir, name));
  }
}

function listSoundFiles() {
  const files = new Map();
  addSoundsFromDir(files, config.soundsDir, '');
  addSoundsFromDir(files, config.uploadsSoundsDir, 'uploads/');
  return files;
}

function resolveSoundPath(soundFile) {
  if (!soundFile) {
    return null;
  }

  if (soundFile.startsWith('uploads/')) {
    const name = soundFile.slice('uploads/'.length);
    const full = path.join(config.uploadsSoundsDir, name);
    if (fs.existsSync(full)) {
      return full;
    }
    return null;
  }

  const local = path.join(config.soundsDir, soundFile);
  if (fs.existsSync(local)) {
    return local;
  }

  const uploaded = path.join(config.uploadsSoundsDir, soundFile);
  if (fs.existsSync(uploaded)) {
    return uploaded;
  }

  return null;
}

function getSoundForTap(tapId) {
  const db = getDb();
  const tap = db.prepare('SELECT sound_file FROM taps WHERE id = ?').get(tapId);

  if (tap && tap.sound_file) {
    const tapPath = resolveSoundPath(tap.sound_file);
    if (tapPath) {
      return tapPath;
    }
  }

  const defaultFile = getSetting('default_sound_file');
  return resolveSoundPath(defaultFile);
}

function onPlayerError(players, index, filePath) {
  tryPlay(players, index + 1, filePath);
}

function tryPlay(players, index, filePath) {
  if (index >= players.length) {
    console.warn('[sound] no audio player found for', filePath);
    return;
  }

  const player = players[index];
  const child = spawn(player.cmd, player.args, {
    stdio: 'ignore',
    detached: true,
  });

  child.on('error', onPlayerError.bind(null, players, index, filePath));
  child.unref();
}

function playersFor(filePath) {
  const lower = filePath.toLowerCase();
  // aplay is much faster to start on Pi Zero than ffplay — prefer it for WAV.
  if (lower.endsWith('.wav')) {
    return [
      { cmd: 'aplay', args: ['-q', filePath] },
      { cmd: 'paplay', args: [filePath] },
      { cmd: 'ffplay', args: ['-nodisp', '-autoexit', '-loglevel', 'quiet', filePath] },
    ];
  }

  return [
    { cmd: 'mpg123', args: ['-q', filePath] },
    { cmd: 'paplay', args: [filePath] },
    { cmd: 'ffplay', args: ['-nodisp', '-autoexit', '-loglevel', 'quiet', filePath] },
    { cmd: 'aplay', args: ['-q', filePath] },
  ];
}

function playFile(filePath) {
  if (!filePath) {
    console.warn('[sound] no sound file to play');
    return;
  }

  if (!fs.existsSync(filePath)) {
    console.warn('[sound] missing file:', filePath);
    return;
  }

  tryPlay(playersFor(filePath), 0, filePath);
}

function playPourSound(tapId) {
  const filePath = getSoundForTap(tapId);
  playFile(filePath);
}

function listAvailableSounds() {
  const map = listSoundFiles();
  return Array.from(map.keys()).sort();
}

module.exports = {
  playPourSound,
  playFile,
  getSoundForTap,
  resolveSoundPath,
  listAvailableSounds,
};
