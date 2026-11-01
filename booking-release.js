import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const client = createClient("https://jzhbqavasikwpxbqjksu.supabase.co", "sb_publishable_KFcwagT3Ho1ivjPv3Oq9zw_FNIaBVpX");
const $ = (id) => document.getElementById(id);
const form = $("bookingForm");
const slots = $("schedule_id");
const submit = $("bookingSubmit");
const champagne = $("champagne_addon");
let state = null;
let fetching = false;
let sending = false;
let serverTime = 0;
let sampledAt = 0;
let requestKey = null;
let requestPayload = null;
let uncertain = false;
let reloadTimer;
let lastFocus;

function message(text, type = "") {
  $("bookingMessage").textContent = text;
  $("bookingMessage").className = `booking-message ${type}`;
}

function updateControls() {
  const open = Boolean(state?.is_open);
  const hasSlots = Boolean(state?.slots?.some((slot) => slot.available));
  slots.disabled = sending || !open || !hasSlots;
  submit.disabled = sending || !open || !hasSlots || !slots.value;
  submit.textContent = sending ? "召 喚 中…" : !state ? "讀 取 中" : !open ? "尚 未 開 放" : !hasSlots ? "本 次 指 名 已 額 滿" : "送 出 指 名";
  champagne.disabled = sending || !open || !slots.value || Number(state?.addon_remaining || 0) < 1;
  if (!sending && (Number(state?.addon_remaining || 0) < 1 || !slots.value)) champagne.checked = false;
  $("champagneTotal").textContent = champagne.checked ? "本次加購金額　100,000 gil" : "本次加購金額　0 gil";
}

function countdown() {
  if (!state) return;
  const now = serverTime + (performance.now() - sampledAt);
  const left = Math.max(0, new Date(state.opens_at).getTime() - now);
  const seconds = Math.ceil(left / 1000);
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor(seconds / 3600) % 24;
  const minutes = Math.floor(seconds / 60) % 60;
  const remainder = seconds % 60;
  $("releaseCountdown").textContent = left ? `${days ? `${days} 天 ` : ""}${String(hours).padStart(2,"0")} : ${String(minutes).padStart(2,"0")} : ${String(remainder).padStart(2,"0")}` : state.is_open ? "指名已開放" : "正在確認開放狀態";
  // The browser never grants access merely because its clock reaches zero.
  if (!left && !state.is_open && state.ready && !fetching) refresh();
}

function render() {
  const selected = slots.value;
  const options = [new Option(state.is_open ? "請選擇指名對象與時段" : "11/02 12:00 開放選擇", "")];
  for (const slot of state.slots || []) {
    if (slot.available) options.push(new Option(`${slot.name}｜${slot.date}`, String(slot.id)));
  }
  slots.replaceChildren(...options);
  if (options.some((option) => option.value === selected)) slots.value = selected;
  $("champagneStock").textContent = Number(state.addon_remaining) > 0 ? `剩餘 ${state.addon_remaining} / ${state.addon_limit} 份` : "本次已售完";
  $("releaseStatus").textContent = state.is_open ? "指名已開放。選擇你的對象，留下這場相遇。" : state.ready ? "11 月 2 日中午 12:00（台灣時間）準時開放，現在可先填寫聯絡資料。" : "排班確認中，預約暫未開放。";
  updateControls();
  countdown();
}

async function refresh() {
  if (fetching || sending || uncertain) return;
  fetching = true;
  try {
    const { data, error } = await client.rpc("get_booking_release_state");
    if (error || !data) throw error || new Error("Missing release");
    state = data;
    serverTime = new Date(data.server_now).getTime();
    sampledAt = performance.now();
    $("releaseRetry").hidden = true;
    render();
  } catch (error) {
    console.error("Booking availability could not be loaded", error);
    state = null;
    $("releaseStatus").textContent = "暫時無法確認名額，請重新讀取。";
    $("releaseCountdown").textContent = "等待連線";
    $("releaseRetry").hidden = false;
    updateControls();
  } finally {
    fetching = false;
  }
}

function showPopup(type, title, text) {
  lastFocus = document.activeElement;
  $("bookingPopupCard").classList.remove("success", "error");
  $("bookingPopupCard").classList.add(type);
  $("bookingPopupTitle").textContent = title;
  $("bookingPopupText").textContent = text;
  $("bookingPopupOverlay").classList.add("show");
  document.body.classList.add("popup-open");
  $("bookingPopupConfirm").focus();
}
function closePopup() {
  $("bookingPopupOverlay").classList.remove("show");
  document.body.classList.remove("popup-open");
  lastFocus?.focus();
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (sending || !state?.is_open || !slots.value || !form.reportValidity()) return;
  const payload = {
    p_schedule_id: Number(slots.value),
    p_customer_name: form.customer_name.value.trim(),
    p_customer_contact: form.customer_contact.value.trim(),
    p_customer_note: form.customer_note.value.trim() || null,
    p_champagne: champagne.checked
  };
  const fingerprint = JSON.stringify(payload);
  if (fingerprint !== requestPayload) {
    requestPayload = fingerprint;
    requestKey = crypto.randomUUID();
  }
  const host = state.slots.find((slot) => slot.id === payload.p_schedule_id)?.name || "對方";
  sending = true;
  message("");
  updateControls();
  try {
    const { data, error } = await client.rpc("reserve_release_slot", { ...payload, p_request_key: requestKey });
    if (error || !data) throw error || new Error("Missing booking response");
    uncertain = false;
    if (!data.success) {
      message(data.message || "此指名已被預約，請重新選擇。", "error");
      showPopup("error", data.code === "not_open" ? "相遇尚未開始" : "請選擇另一場相遇", data.message || "此指名已被搶先預約。");
      requestPayload = null;
    } else {
      let text = `${host}已回應你的指名。\n${slots.selectedOptions[0].textContent}\n`;
      if (data.addon_reserved) text += "\n加購成功｜黏膩相擁 × 1\n加購金額：100,000 gil";
      else if (data.addon_requested) text += "\n相擁加購已被搶先帶走，本次未加購、無加購費用。你的指名預約仍已成功保留。";
      else text += "\n本次未加購黏膩相擁。";
      message("指名預約成功，請保留確認資訊並等待聯絡。", "success");
      showPopup("success", "召喚已被回應", text);
      form.reset();
      requestPayload = null;
      requestKey = null;
    }
  } catch (error) {
    uncertain = true;
    console.error("Booking request failed", error);
    message("連線中斷，暫時無法確認結果。請保留相同資料再次送出，系統會核對重送，避免重複預約。", "error");
  } finally {
    sending = false;
    updateControls();
    await refresh();
  }
});

slots.addEventListener("change", updateControls);
champagne.addEventListener("change", updateControls);
$("releaseRetry").addEventListener("click", refresh);
$("bookingPopupClose").addEventListener("click", closePopup);
$("bookingPopupConfirm").addEventListener("click", closePopup);
$("bookingPopupOverlay").addEventListener("click", (event) => {
  if (event.target === $("bookingPopupOverlay")) closePopup();
});
document.addEventListener("keydown", (event) => {
  if (!$("bookingPopupOverlay").classList.contains("show")) return;
  if (event.key === "Escape") closePopup();
  if (event.key === "Tab") {
    const first = $("bookingPopupClose");
    const last = $("bookingPopupConfirm");
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
  }
});
document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(); });
window.addEventListener("pageshow", refresh);
window.addEventListener("scroll", () => document.querySelector(".site-header")?.classList.toggle("scrolled", window.scrollY > 10), { passive: true });
const tick = setInterval(countdown, 1000);
const poll = setInterval(refresh, 10000);
const channel = client.channel("release-booking-availability")
  .on("postgres_changes", { event: "*", schema: "public", table: "schedule_list" }, () => {
    clearTimeout(reloadTimer);
    reloadTimer = setTimeout(refresh, 150);
  }).subscribe();
window.addEventListener("beforeunload", () => {
  clearInterval(tick); clearInterval(poll); clearTimeout(reloadTimer);
  client.removeChannel(channel);
});
updateControls();
refresh();
