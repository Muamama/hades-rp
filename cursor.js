document.addEventListener("DOMContentLoaded", () => {
  const isFinePointer = window.matchMedia("(hover: hover) and (pointer: fine)").matches;
  const dogTargetSelector = ".logo img, .hero-logo img";
  const feedCooldown = 860;

  let lastFeedAt = 0;

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

  function spawnFeedBurst(mouthX, mouthY) {
    const burst = document.createElement("div");
    burst.className = "gil-feed-burst";
    burst.style.left = mouthX + "px";
    burst.style.top = mouthY + "px";

    const chomp = document.createElement("div");
    chomp.className = "gil-feed-chomp";
    chomp.innerHTML = "<i></i><b></b>";
    burst.appendChild(chomp);

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

  function biteDog(target) {
    target.classList.remove("doggy-feeding");
    void target.offsetWidth;
    target.classList.add("doggy-feeding");

    window.setTimeout(() => {
      target.classList.remove("doggy-feeding");
    }, 780);
  }

  function triggerTouchFeed(feedTarget, x, y) {
    const now = Date.now();
    if (now - lastFeedAt < feedCooldown) return;

    lastFeedAt = now;

    const coin = document.createElement("div");
    coin.className = "gil-touch-coin is-eaten";
    coin.style.left = x + "px";
    coin.style.top = y + "px";
    coin.style.setProperty("--feed-x", feedTarget.mouthX - x + "px");
    coin.style.setProperty("--feed-y", feedTarget.mouthY - y + "px");

    document.body.appendChild(coin);
    biteDog(feedTarget.target);
    spawnFeedBurst(feedTarget.mouthX, feedTarget.mouthY);

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
          triggerTouchFeed(feedTarget, touch.clientX, touch.clientY);
        }
      },
      { passive: true }
    );

    document.addEventListener("click", (e) => {
      const feedTarget = getDogFeedTarget(e.clientX, e.clientY);
      if (feedTarget) {
        triggerTouchFeed(feedTarget, e.clientX, e.clientY);
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
    const now = Date.now();
    if (now - lastFeedAt < feedCooldown) return;

    lastFeedAt = now;

    document.body.classList.add("gil-feeding");
    cursor.style.setProperty("--feed-x", feedTarget.mouthX - mouseX + "px");
    cursor.style.setProperty("--feed-y", feedTarget.mouthY - mouseY + "px");
    cursor.classList.remove("is-eaten");
    void cursor.offsetWidth;
    cursor.classList.add("is-eaten");

    biteDog(feedTarget.target);
    spawnFeedBurst(feedTarget.mouthX, feedTarget.mouthY);

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
