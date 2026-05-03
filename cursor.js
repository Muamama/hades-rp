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

  document.addEventListener("mousemove", (e) => {
    mouseX = e.clientX;
    mouseY = e.clientY;

    cursor.style.left = mouseX + "px";
    cursor.style.top = mouseY + "px";

    document.body.classList.add("gil-cursor-active");
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
