(function () {
  const audioSrc = window.MINGJIE_BGM_SRC || "audio/FFXIV%20Pulse%20Remix%20Album%20-%20Rise%20%28Alexander%27s%20Theme%29%20-%20Sophie%20%28Desucrate%29%20%28youtube%29.mp3";
  const storagePrefix = "mingjie:bgm:";
  const defaultVolume = 0.17;
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
    ? Math.min(savedVolume, defaultVolume)
    : defaultVolume;
  localStorage.setItem(storagePrefix + "volume", String(audio.volume));

  const toggle = document.createElement("button");
  toggle.className = "site-bgm-switch";
  toggle.type = "button";
  toggle.setAttribute("aria-label", "開啟音樂");
  toggle.setAttribute("aria-pressed", "false");
  toggle.innerHTML = '<span class="site-bgm-switch-icon" aria-hidden="true"></span><span class="site-bgm-switch-text">音樂</span>';

  document.body.appendChild(audio);
  document.body.appendChild(toggle);

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
    toggle.classList.toggle("is-on", isPlaying);
    toggle.setAttribute("aria-pressed", String(isPlaying));
    toggle.setAttribute("aria-label", isPlaying ? "關閉音樂" : "開啟音樂");
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
      .catch(function () {
        updateBgmVisualState();
      });
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

  audio.addEventListener("loadedmetadata", applyResumeTime, { once: true });
  audio.addEventListener("timeupdate", function () {
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

  if (wasPlaying) {
    playBgm();
  }
}());
