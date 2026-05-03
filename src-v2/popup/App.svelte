<script>
  import { settings } from '../lib/settings.svelte.js';
  import { loadLanguage, resolveLanguage } from '../lib/i18n.svelte.js';
  import Clock from '../components/Clock.svelte';
  import VideoBackground from '../components/VideoBackground.svelte';

  $effect(() => {
    loadLanguage(resolveLanguage(settings.userLanguage));
  });
</script>

<VideoBackground />

<main>
  <div class="centered">
    <Clock />
  </div>
</main>

<style>
  :global(body) {
    margin: 0;
    background: #000;
    color: #eee;
    font-family: system-ui, sans-serif;
    overflow: hidden;
  }
  main {
    min-height: 100vh;
  }
  .centered {
    position: absolute;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    text-align: center;
  }
</style>
