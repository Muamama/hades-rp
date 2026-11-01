(() => {
  const dialog = document.getElementById("homeEventDialog");
  const openButton = document.getElementById("homeEventOpen");
  const video = document.getElementById("homeEventVideo");
  const endsAt = new Date("2026-11-08T00:00:00+08:00").getTime();
  const sessionKey = "hades:nov07:announcement-seen";
  let resumeBgm = false;
  function open() { if (!dialog.open) dialog.showModal(); }
  function close() { dialog.close(); }
  function resumeMusic() {
    const bgm = document.getElementById("siteBgmAudio");
    if (resumeBgm && bgm) bgm.play().catch(() => {});
    resumeBgm = false;
  }
  openButton.addEventListener("click", open);
  document.getElementById("homeEventClose").addEventListener("click", close);
  document.getElementById("homeEventDismiss").addEventListener("click", close);
  dialog.addEventListener("click", (event) => {
    const rect = dialog.getBoundingClientRect();
    if (event.target === dialog && (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom)) close();
  });
  video.addEventListener("play", () => {
    const bgm = document.getElementById("siteBgmAudio");
    if (bgm && !bgm.paused) { resumeBgm = true; bgm.pause(); }
  });
  video.addEventListener("pause", resumeMusic);
  video.addEventListener("ended", resumeMusic);
  dialog.addEventListener("close", () => {
    video.pause();
    resumeMusic();
    openButton.focus({ preventScroll:true });
  });
  if (Date.now() >= endsAt) { openButton.parentElement.hidden = true; return; }
  let seen = false;
  try { seen = sessionStorage.getItem(sessionKey) === "true"; sessionStorage.setItem(sessionKey,"true"); } catch (_) { /* Storage may be unavailable in private browsing. */ }
  if (!seen) open();
})();
