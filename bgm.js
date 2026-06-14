(function () {
  const audioSrc = window.MINGJIE_BGM_SRC || "audio/FFXIV%20Pulse%20Remix%20Album%20-%20Rise%20%28Alexander%27s%20Theme%29%20-%20Sophie%20%28Desucrate%29%20%28youtube%29.mp3";
  const storagePrefix = "mingjie:bgm:";
  const defaultVolume = 0.17;
  const savedVolume = Number(localStorage.getItem(storagePrefix + "volume"));
  const savedTime = Number(sessionStorage.getItem(storagePrefix + "time"));
  const savedTimestamp = Number(sessionStorage.getItem(storagePrefix + "savedAt"));
  const wasPlaying = sessionStorage.getItem(storagePrefix + "playing") === "true";
  let hasTriedToPlay = false;
  let hasAppliedResumeTime = false;
  let lastPersistedAt = 0;
  let pendingPersist = 0;
  const gestureEvents = ["pointerdown", "touchstart", "click"];

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

  document.body.appendChild(audio);

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
    if (hasTriedToPlay && !audio.paused) return;

    hasTriedToPlay = true;
    applyResumeTime();
    return audio.play()
      .then(function () {
        removeGestureStartEvents();
      })
      .catch(function () {
        hasTriedToPlay = false;
      });
  }

  function removeGestureStartEvents() {
    gestureEvents.forEach(function (eventName) {
      window.removeEventListener(eventName, playBgm, true);
      document.removeEventListener(eventName, playBgm, true);
    });
  }

  function bindStartEvents() {
    const scrollOptions = { passive: true, once: true, capture: true };
    const onceOptions = { passive: true, once: true };
    const prefetchedLinks = new Set();

    window.addEventListener("scroll", playBgm, scrollOptions);
    document.addEventListener("scroll", playBgm, scrollOptions);
    window.addEventListener("wheel", playBgm, onceOptions);
    window.addEventListener("touchmove", playBgm, onceOptions);
    gestureEvents.forEach(function (eventName) {
      window.addEventListener(eventName, playBgm, { passive: true, capture: true });
      document.addEventListener(eventName, playBgm, { passive: true, capture: true });
    });
    window.addEventListener("keydown", function (event) {
      if (["ArrowDown", "ArrowUp", "PageDown", "PageUp", "Home", "End", " "].includes(event.key)) {
        playBgm();
      }
    }, { passive: true });

    document.querySelectorAll("main, .page-wrapper").forEach(function (scrollTarget) {
      scrollTarget.addEventListener("scroll", playBgm, scrollOptions);
      scrollTarget.addEventListener("wheel", playBgm, onceOptions);
      scrollTarget.addEventListener("touchmove", playBgm, onceOptions);
    });

    function prefetchLink(event) {
      const link = event.target.closest && event.target.closest("a[href]");
      if (!link || link.target || link.hasAttribute("download")) return;
      if (link.origin !== window.location.origin || prefetchedLinks.has(link.href)) return;

      prefetchedLinks.add(link.href);
      const prefetch = document.createElement("link");
      prefetch.rel = "prefetch";
      prefetch.href = link.href;
      document.head.appendChild(prefetch);
    }

    document.addEventListener("mouseover", prefetchLink, { passive: true });
    document.addEventListener("focusin", prefetchLink);
  }

  audio.addEventListener("loadedmetadata", applyResumeTime, { once: true });
  audio.addEventListener("timeupdate", function () {
    saveState(false);
  });
  audio.addEventListener("play", function () {
    saveState(false);
  });
  audio.addEventListener("pause", function () {
    saveState(true);
  });
  window.addEventListener("pagehide", function () {
    saveState(true);
  });

  bindStartEvents();

  if (wasPlaying) {
    playBgm();
  }
}());
