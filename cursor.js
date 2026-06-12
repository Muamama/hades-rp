document.addEventListener("DOMContentLoaded", () => {
  const isFinePointer = window.matchMedia("(hover: hover) and (pointer: fine)").matches;
  const dogTargetSelector = ".logo img, .hero-logo img";
  const feedCooldown = 860;

  const lastFeedByTarget = new WeakMap();
  let lastTouchFeedAt = 0;

  function canFeed(target) {
    const now = Date.now();
    const lastFeedAt = lastFeedByTarget.get(target) || 0;

    if (now - lastFeedAt < feedCooldown) return false;

    lastFeedByTarget.set(target, now);
    return true;
  }

  function getDogFeedTarget(clientX, clientY) {
    const targets = document.querySelectorAll(dogTargetSelector);

    for (const target of targets) {
      const rect = target.getBoundingClientRect();
      if (!rect.width || !rect.height) continue;

      const padding = Math.max(12, Math.min(rect.width, rect.height) * 0.18);
      const inPaddedRect =
        clientX >= rect.left - padding &&
        clientX <= rect.right + padding &&
        clientY >= rect.top - padding &&
        clientY <= rect.bottom + padding;

      if (!inPaddedRect) continue;

      const mouthClientX = rect.left + rect.width * 0.48;
      const mouthClientY = rect.top + rect.height * 0.54;
      const radiusX = Math.max(20, rect.width * 0.42);
      const radiusY = Math.max(20, rect.height * 0.42);
      const normalized =
        ((clientX - mouthClientX) * (clientX - mouthClientX)) / (radiusX * radiusX) +
        ((clientY - mouthClientY) * (clientY - mouthClientY)) / (radiusY * radiusY);

      if (normalized <= 1) {
        return {
          target,
          mouthX: mouthClientX,
          mouthY: mouthClientY,
          mouthPageX: mouthClientX + window.scrollX,
          mouthPageY: mouthClientY + window.scrollY
        };
      }
    }

    return null;
  }

  function spawnFeedBurst(mouthPageX, mouthPageY) {
    const burst = document.createElement("div");
    burst.className = "gil-feed-burst";
    burst.style.left = mouthPageX + "px";
    burst.style.top = mouthPageY + "px";

    for (let i = 0; i < 9; i += 1) {
      const spark = document.createElement("span");
      const angle = (Math.PI * 2 * i) / 9 + Math.random() * 0.34;
      const distance = 16 + Math.random() * 28;

      spark.style.setProperty("--spark-x", Math.cos(angle) * distance + "px");
      spark.style.setProperty("--spark-y", Math.sin(angle) * distance + "px");
      spark.style.setProperty("--spark-delay", Math.random() * 0.08 + "s");
      burst.appendChild(spark);
    }

    document.body.appendChild(burst);
    window.setTimeout(() => burst.remove(), 980);
  }

  function biteDog(feedTarget) {
    const target = feedTarget.target;

    target.classList.remove("doggy-feeding");
    void target.offsetWidth;
    target.classList.add("doggy-feeding");

    window.setTimeout(() => {
      target.classList.remove("doggy-feeding");
    }, 780);
  }

  function triggerTouchFeed(feedTarget, clientX, clientY, pageX, pageY) {
    if (!canFeed(feedTarget.target)) return;

    const coin = document.createElement("div");
    coin.className = "gil-touch-coin is-eaten";
    coin.style.left = pageX + "px";
    coin.style.top = pageY + "px";
    coin.style.setProperty("--feed-x", feedTarget.mouthPageX - pageX + "px");
    coin.style.setProperty("--feed-y", feedTarget.mouthPageY - pageY + "px");

    document.body.appendChild(coin);
    biteDog(feedTarget);
    spawnFeedBurst(feedTarget.mouthPageX, feedTarget.mouthPageY);

    window.setTimeout(() => coin.remove(), 880);
  }

  if (!isFinePointer) {
    document.addEventListener(
      "touchstart",
      (e) => {
        const touch = e.changedTouches && e.changedTouches[0];
        if (!touch) return;

        const feedTarget = getDogFeedTarget(touch.clientX, touch.clientY);
        if (feedTarget) {
          lastTouchFeedAt = Date.now();
          triggerTouchFeed(feedTarget, touch.clientX, touch.clientY, touch.pageX, touch.pageY);
        }
      },
      { passive: true }
    );

    document.addEventListener("click", (e) => {
      if (Date.now() - lastTouchFeedAt < 700) return;

      const feedTarget = getDogFeedTarget(e.clientX, e.clientY);
      if (feedTarget) {
        triggerTouchFeed(
          feedTarget,
          e.clientX,
          e.clientY,
          e.clientX + window.scrollX,
          e.clientY + window.scrollY
        );
      }
    });

    return;
  }

  const cursor = document.createElement("div");
  const glow = document.createElement("div");

  cursor.className = "gil-cursor";
  glow.className = "gil-cursor-glow";

  document.body.appendChild(glow);
  document.body.appendChild(cursor);

  let mouseX = 0;
  let mouseY = 0;
  let glowX = 0;
  let glowY = 0;

  function triggerMouseFeed(feedTarget) {
    if (!canFeed(feedTarget.target)) return;

    document.body.classList.add("gil-feeding");
    cursor.style.setProperty("--feed-x", feedTarget.mouthX - mouseX + "px");
    cursor.style.setProperty("--feed-y", feedTarget.mouthY - mouseY + "px");
    cursor.classList.remove("is-eaten");
    void cursor.offsetWidth;
    cursor.classList.add("is-eaten");

    biteDog(feedTarget);
    spawnFeedBurst(feedTarget.mouthPageX, feedTarget.mouthPageY);

    window.setTimeout(() => {
      cursor.classList.remove("is-eaten");
      document.body.classList.remove("gil-feeding");
    }, 820);
  }

  document.addEventListener("mousemove", (e) => {
    mouseX = e.clientX;
    mouseY = e.clientY;

    cursor.style.left = mouseX + "px";
    cursor.style.top = mouseY + "px";

    document.body.classList.add("gil-cursor-active");

    const feedTarget = getDogFeedTarget(mouseX, mouseY);
    if (feedTarget) {
      triggerMouseFeed(feedTarget);
    }
  });

  function animateGlow() {
    glowX += (mouseX - glowX) * 0.2;
    glowY += (mouseY - glowY) * 0.2;

    glow.style.left = glowX + "px";
    glow.style.top = glowY + "px";

    requestAnimationFrame(animateGlow);
  }

  animateGlow();

  const clickableSelector = `
    a,
    button,
    input,
    textarea,
    select,
    label,
    summary,
    [onclick],
    [role="button"],
    .nav a,
    .mobile-menu-btn,
    .host-card,
    .service-card,
    .rate-card,
    .schedule-card,
    .booking-card,
    .echo-card,
    .leaderboard-card,
    .time-card,
    .footer a,
    .site-footer a
  `;

  document.addEventListener("mouseover", (e) => {
    if (e.target.closest(clickableSelector)) {
      document.body.classList.add("gil-hovering");
    }
  });

  document.addEventListener("mouseout", (e) => {
    if (e.target.closest(clickableSelector)) {
      document.body.classList.remove("gil-hovering");
    }
  });

  document.addEventListener("mousedown", () => {
    document.body.classList.add("gil-clicking");
  });

  document.addEventListener("mouseup", () => {
    document.body.classList.remove("gil-clicking");
  });

  document.addEventListener("mouseleave", () => {
    document.body.classList.remove("gil-cursor-active");
  });

  document.addEventListener("mouseenter", () => {
    document.body.classList.add("gil-cursor-active");
  });
});
