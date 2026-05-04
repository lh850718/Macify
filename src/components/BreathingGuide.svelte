<script>
  import { fade } from 'svelte/transition';
  import { settings } from '../lib/settings.svelte.js';
  import { t } from '../lib/i18n.svelte.js';
  import { zen } from '../lib/zen.svelte.js';

  // Three breathing patterns, all expressed as a sequence of phases.
  // Scale endpoints: inhale grows the circle, exhale shrinks, hold
  // stays put. Slight overshoot in scale (0.55 → 1.45) gives a more
  // visible breath without dominating the screen.
  const PATTERNS = {
    coherent: [
      { phase: 'inhale', durationMs: 5000, scale: 1.45 },
      { phase: 'exhale', durationMs: 5000, scale: 0.55 },
    ],
    box: [
      { phase: 'inhale', durationMs: 4000, scale: 1.45 },
      { phase: 'hold', durationMs: 4000, scale: 1.45 },
      { phase: 'exhale', durationMs: 4000, scale: 0.55 },
      { phase: 'hold', durationMs: 4000, scale: 0.55 },
    ],
    '478': [
      { phase: 'inhale', durationMs: 4000, scale: 1.45 },
      { phase: 'hold', durationMs: 7000, scale: 1.45 },
      { phase: 'exhale', durationMs: 8000, scale: 0.55 },
    ],
  };

  let scale = $state(0.55);
  let durationMs = $state(5000);
  let phase = $state('exhale');

  // Tick through pattern phases for as long as the component is mounted.
  // Mount is gated by {#if zen.active && settings.zenBreathing} in the
  // parent — so unmount happens automatically on Zen exit, taking the
  // timer with it.
  $effect(() => {
    const pattern = PATTERNS[settings.zenBreathingPattern] ?? PATTERNS.coherent;
    let i = 0;
    let timer = null;

    function step() {
      const s = pattern[i];
      phase = s.phase;
      durationMs = s.durationMs;
      scale = s.scale;
      i = (i + 1) % pattern.length;
      timer = setTimeout(step, s.durationMs);
    }
    step();
    return () => {
      if (timer) clearTimeout(timer);
    };
  });

  const phaseLabel = $derived.by(() => {
    if (phase === 'inhale') return t('zen_breath_inhale');
    if (phase === 'exhale') return t('zen_breath_exhale');
    return t('zen_breath_hold');
  });
</script>

<div class="overlay" transition:fade={{ duration: 800 }}>
  <!-- Stack uses position:relative so the circle (absolutely positioned
       inside) and the label (also absolutely positioned) overlay at
       center. Critical: label is a SIBLING of the circle, not a child —
       so the circle's transform: scale() doesn't enlarge/shrink the
       label text along with it. -->
  <div class="stack">
    <div
      class="circle"
      style:transform={`scale(${scale})`}
      style:transition={`transform ${durationMs}ms ease-in-out`}
    ></div>
    <span class="label">{phaseLabel}</span>
  </div>
</div>

<style>
  .overlay {
    position: fixed;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    pointer-events: none;
    z-index: 10;
  }
  .stack {
    position: relative;
    width: 220px;
    height: 220px;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .circle {
    position: absolute;
    inset: 0;
    border-radius: 50%;
    background: radial-gradient(
      circle at center,
      rgba(255, 255, 255, 0.18) 0%,
      rgba(255, 255, 255, 0.08) 60%,
      rgba(255, 255, 255, 0) 100%
    );
    backdrop-filter: blur(2px);
    will-change: transform;
  }
  .label {
    position: relative;
    z-index: 1;
    color: rgba(255, 255, 255, 0.75);
    font-size: 0.95rem;
    letter-spacing: 0.2em;
    text-transform: uppercase;
    text-shadow: 0 1px 4px rgba(0, 0, 0, 0.5);
    user-select: none;
  }
</style>
