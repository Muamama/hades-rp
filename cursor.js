// ================================
// 冥界金幣滑鼠游標
// ================================

document.addEventListener("DOMContentLoaded", () => {
  const isFinePointer = window.matchMedia("(hover: hover) and (pointer: fine)").matches;

  if (!isFinePointer) return;

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
  let lastFeedAt = 0;
  let currentDogTarget = null;

  const dogTargetSelector = ".logo img, .hero-logo img";
  const feedCooldown = 520;

  function getDogFeedTarget(x, y) {
    const targets = document.querySelectorAll(dogTargetSelector);

    for (const target of targets) {
      const rect = target.getBoundingClientRect();
      if (!rect.width || !rect.height) continue;

      const padding = Math.max(12, Math.min(rect.width, rect.height) * 0.18);
      const inPaddedRect =
        x >= rect.left - padding &&
        x <= rect.right + padding &&
        y >= rect.top - padding &&
        y <= rect.bottom + padding;

      if (!inPaddedRect) continue;

      const mouthX = rect.left + rect.width * 0.48;
      const mouthY = rect.top + rect.height * 0.54;
      const radiusX = Math.max(20, rect.width * 0.42);
      const radiusY = Math.max(20, rect.height * 0.42);
      const normalized =
        ((x - mouthX) * (x - mouthX)) / (radiusX * radiusX) +
        ((y - mouthY) * (y - mouthY)) / (radiusY * radiusY);

      if (normalized <= 1) {
        return { target, mouthX, mouthY };
      }
    }

    return null;
  }

  function spawnFeedEffect(x, y, mouthX, mouthY) {
    const burst = document.createElement("div");
    burst.className = "gil-feed-burst";
    burst.style.left = mouthX + "px";
    burst.style.top = mouthY + "px";

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
    window.setTimeout(() => burst.remove(), 720);

    cursor.style.setProperty("--feed-x", mouthX - x + "px");
    cursor.style.setProperty("--feed-y", mouthY - y + "px");
  }

  function triggerDogFeed(feedTarget) {
    const now = Date.now();
    if (now - lastFeedAt < feedCooldown) return;

    lastFeedAt = now;

    document.body.classList.add("gil-feeding");
    cursor.classList.remove("is-eaten");
    void cursor.offsetWidth;
    cursor.classList.add("is-eaten");

    feedTarget.target.classList.remove("doggy-feeding");
    void feedTarget.target.offsetWidth;
    feedTarget.target.classList.add("doggy-feeding");

    spawnFeedEffect(mouseX, mouseY, feedTarget.mouthX, feedTarget.mouthY);

    window.setTimeout(() => {
      cursor.classList.remove("is-eaten");
      document.body.classList.remove("gil-feeding");
    }, 430);

    window.setTimeout(() => {
      feedTarget.target.classList.remove("doggy-feeding");
    }, 520);
  }

  document.addEventListener("mousemove", (e) => {
    mouseX = e.clientX;
    mouseY = e.clientY;

    cursor.style.left = mouseX + "px";
    cursor.style.top = mouseY + "px";

    document.body.classList.add("gil-cursor-active");

    const feedTarget = getDogFeedTarget(mouseX, mouseY);

    if (feedTarget) {
      if (currentDogTarget !== feedTarget.target) {
        currentDogTarget = feedTarget.target;
      }
      triggerDogFeed(feedTarget);
    } else {
      currentDogTarget = null;
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
