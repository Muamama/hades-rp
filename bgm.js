(function () {
  const audioSrc = window.MINGJIE_BGM_SRC || "audio/FFXIV%20Pulse%20Remix%20Album%20-%20Rise%20%28Alexander%27s%20Theme%29%20-%20Sophie%20%28Desucrate%29%20%28youtube%29.mp3";
  const storagePrefix = "mingjie:bgm:";
  const defaultVolume = 0.17;
  const maxVolume = 0.34;
  const savedVolume = Number(localStorage.getItem(storagePrefix + "volume"));
  const savedTime = Number(sessionStorage.getItem(storagePrefix + "time"));
  const savedTimestamp = Number(sessionStorage.getItem(storagePrefix + "savedAt"));
  const wasPlaying = sessionStorage.getItem(storagePrefix + "playing") === "true";
  let hasAppliedResumeTime = false;
  let lastPersistedAt = 0;
  let pendingPersist = 0;

  const audio = document.createElement("audio");
  audio.id = "siteBgmAudio";
  audio.src = audioSrc;
  audio.loop = true;
  audio.preload = "auto";
  audio.playsInline = true;
  audio.volume = Number.isFinite(savedVolume) && savedVolume > 0
    ? Math.min(savedVolume, maxVolume)
    : defaultVolume;
  localStorage.setItem(storagePrefix + "volume", String(audio.volume));

  const drawer = document.createElement("div");
  drawer.className = "site-bgm-drawer";
  drawer.innerHTML = [
    '<button class="site-bgm-tab" type="button" aria-label="Open music player" aria-expanded="false">',
    '  <span class="site-bgm-tab-mark" aria-hidden="true"></span>',
    "</button>",
    '<div class="site-bgm-player">',
    '  <button class="site-bgm-play" type="button" aria-label="Play music" aria-pressed="false">',
    '    <span class="site-bgm-play-icon" aria-hidden="true"></span>',
    "  </button>",
    '  <div class="site-bgm-track" aria-hidden="true">',
    '    <div class="site-bgm-track-art"></div>',
    '    <div class="site-bgm-track-meta">',
    '      <span class="site-bgm-track-title">Rise</span>',
    '      <span class="site-bgm-track-subtitle">FFXIV Pulse</span>',
    '      <span class="site-bgm-progress"><span></span></span>',
    "    </div>",
    "  </div>",
    '  <label class="site-bgm-volume">',
    '    <span class="site-bgm-volume-icon" aria-hidden="true"></span>',
    '    <input type="range" min="0" max="' + String(maxVolume) + '" step="0.01" aria-label="Music volume">',
    "  </label>",
    "</div>",
  ].join("");

  document.body.appendChild(audio);
  document.body.appendChild(drawer);

  const drawerToggle = drawer.querySelector(".site-bgm-tab");
  const player = drawer.querySelector(".site-bgm-player");
  const toggle = drawer.querySelector(".site-bgm-play");
  const volumeInput = drawer.querySelector(".site-bgm-volume input");
  const progressBar = drawer.querySelector(".site-bgm-progress span");
  volumeInput.value = String(audio.volume);

  function setDrawerOpen(isOpen) {
    drawer.classList.toggle("is-open", isOpen);
    drawerToggle.setAttribute("aria-expanded", String(isOpen));
    drawerToggle.setAttribute("aria-label", isOpen ? "Close music player" : "Open music player");
    localStorage.setItem(storagePrefix + "drawerOpen", String(isOpen));
  }

  function getResumeTime() {
    if (!Number.isFinite(savedTime) || savedTime < 0) return 0;
    if (!wasPlaying || !Number.isFinite(savedTimestamp)) return savedTime;

    const elapsed = Math.max(0, (Date.now() - savedTimestamp) / 1000);
    return savedTime + elapsed;
  }

  function applyResumeTime() {
    if (hasAppliedResumeTime) return;

    const resumeTime = getResumeTime();
    if (!resumeTime) {
      hasAppliedResumeTime = true;
      return;
    }

    if (Number.isFinite(audio.duration) && audio.duration > 0) {
      audio.currentTime = resumeTime % audio.duration;
      hasAppliedResumeTime = true;
      return;
    }

    audio.currentTime = resumeTime;
    hasAppliedResumeTime = true;
  }

  function updateBgmVisualState() {
    const isPlaying = !audio.paused;

    document.body.classList.toggle("bgm-playing", isPlaying);
    drawer.classList.toggle("is-on", isPlaying);
    toggle.setAttribute("aria-pressed", String(isPlaying));
    toggle.setAttribute("aria-label", isPlaying ? "Pause music" : "Play music");
  }

  function updateProgress() {
    if (!Number.isFinite(audio.duration) || audio.duration <= 0) {
      progressBar.style.width = "0%";
      return;
    }

    progressBar.style.width = String(Math.min(100, (audio.currentTime / audio.duration) * 100)) + "%";
  }

  function persistState(now) {
    lastPersistedAt = now;
    sessionStorage.setItem(storagePrefix + "time", String(audio.currentTime || 0));
    sessionStorage.setItem(storagePrefix + "savedAt", String(now));
    sessionStorage.setItem(storagePrefix + "playing", String(!audio.paused));
  }

  function schedulePersist(now) {
    if (pendingPersist) return;

    const schedule = window.requestIdleCallback || window.requestAnimationFrame || window.setTimeout;
    pendingPersist = schedule(function () {
      pendingPersist = 0;
      persistState(now);
    });
  }

  function saveState(force) {
    const now = Date.now();
    if (!force && now - lastPersistedAt < 2400) return;

    if (force) {
      persistState(now);
      return;
    }

    schedulePersist(now);
  }

  function playBgm() {
    if (!audio.paused) return Promise.resolve();

    applyResumeTime();
    return audio.play()
      .then(function () {
        updateBgmVisualState();
        saveState(false);
      })
      .catch(updateBgmVisualState);
  }

  function pauseBgm() {
    audio.pause();
    updateBgmVisualState();
    saveState(true);
  }

  toggle.addEventListener("click", function () {
    if (audio.paused) {
      playBgm();
      return;
    }

    pauseBgm();
  });

  drawerToggle.addEventListener("click", function () {
    setDrawerOpen(!drawer.classList.contains("is-open"));
  });

  volumeInput.addEventListener("input", function () {
    audio.volume = Number(volumeInput.value);
    localStorage.setItem(storagePrefix + "volume", String(audio.volume));
  });

  audio.addEventListener("loadedmetadata", function () {
    applyResumeTime();
    updateProgress();
  }, { once: true });
  audio.addEventListener("timeupdate", function () {
    updateProgress();
    saveState(false);
  });
  audio.addEventListener("play", function () {
    updateBgmVisualState();
    saveState(false);
  });
  audio.addEventListener("pause", function () {
    updateBgmVisualState();
    saveState(true);
  });
  audio.addEventListener("ended", updateBgmVisualState);
  window.addEventListener("pagehide", function () {
    saveState(true);
  });

  updateBgmVisualState();
  updateProgress();
  setDrawerOpen(localStorage.getItem(storagePrefix + "drawerOpen") === "true");

  if (wasPlaying) {
    playBgm();
  }
}());
