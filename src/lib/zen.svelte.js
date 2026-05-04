// Shared Zen mode state. Both the on-screen Zen button (ZenMode.svelte)
// and the break-reminder pill (ZenReminderPill.svelte) call enterZen()
// from here, so a session can start whether or not the new-tab UI is
// showing the button at the moment.
//
// Storage key:
//   lastZenSessionAt — ms timestamp set on every enterZen(); the reminder
//   pill uses this to compute "minutes since last session".

import { settings } from './settings.svelte.js';

const MUSIC_BASE = `${import.meta.env.VITE_MACIFY_BASE}/music/`;
const TRACK_COUNT = 40;

/** Reactive state observable from any component. */
export const zen = $state({ active: false });

/** Set by ZenMode.svelte once its <audio> element mounts. */
let audioEl = null;
let autoExitTimer = null;
let fullscreenListener = null;

export function bindAudioElement(el) {
  audioEl = el;
}

function randomTrackUrl() {
  const n = Math.floor(Math.random() * TRACK_COUNT) + 1;
  return MUSIC_BASE + `music${String(n).padStart(5, '0')}.mp3`;
}

/**
 * Enter Zen mode: fullscreen the video stage, optionally start music,
 * optionally start the auto-exit timer. Stamps lastZenSessionAt so the
 * reminder pill cooldown begins now.
 *
 * Must be called from a user gesture (browser fullscreen + autoplay rules).
 */
export async function enterZen() {
  // Fullscreen the stage div (set up in popup/App.svelte) so any overlay
  // siblings — breathing guide, etc — are part of the fullscreen view.
  // Fall back to the video element if the stage somehow isn't there.
  const stage =
    document.getElementById('zen-stage') ?? document.querySelector('video');
  if (!stage) return;

  try {
    await stage.requestFullscreen();
  } catch (e) {
    console.warn('Fullscreen request failed:', e);
    return;
  }

  zen.active = true;

  // Reset the reminder cooldown timer.
  try {
    await chrome.storage.local.set({ lastZenSessionAt: Date.now() });
  } catch {
    // best-effort, swallow
  }

  // Music — opt-out via settings.
  if (settings.zenMusic && audioEl) {
    try {
      audioEl.src = randomTrackUrl();
      await audioEl.play();
    } catch (e) {
      console.warn('Zen music playback failed:', e);
    }
  }

  // Auto-exit timer.
  const minutes = Number(settings.zenAutoExitMinutes) || 0;
  if (settings.zenAutoExitEnabled && minutes > 0) {
    autoExitTimer = setTimeout(() => {
      exitZen();
    }, minutes * 60_000);
  }

  // Listen once for the user (or auto-exit) leaving fullscreen, so we
  // tear everything down in one place.
  if (!fullscreenListener) {
    fullscreenListener = () => {
      if (!document.fullscreenElement) {
        teardown();
      }
    };
    document.addEventListener('fullscreenchange', fullscreenListener);
  }
}

/**
 * Programmatically exit. Same effect as the user pressing Esc — leaving
 * fullscreen triggers the listener which calls teardown().
 */
export function exitZen() {
  if (document.fullscreenElement) {
    document.exitFullscreen();
  } else {
    teardown();
  }
}

function teardown() {
  zen.active = false;
  if (audioEl) {
    audioEl.pause();
    audioEl.currentTime = 0;
  }
  if (autoExitTimer) {
    clearTimeout(autoExitTimer);
    autoExitTimer = null;
  }
}
