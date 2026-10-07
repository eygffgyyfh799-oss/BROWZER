const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'carplay';
const $ = (id) => document.getElementById(id);

const post = (cb, data = {}) =>
  fetch(`https://${RES}/${cb}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  }).then((r) => r.json()).catch(() => null);

let ytReady = false;
const sessions = {};         // [plate] = { state, at } كل السيارات الشغالة (من السيرفر)
const streams = new Map();   // [plate] = مشغل يوتيوب لكل سيارة قريبة تنسمع
let mix = {};                // [plate] = قوة الصوت 3D عندك (0 - 1) محسوبة باللعبة
let focus = null;            // لوحة السيارة اللي أنت فيها
let fav = [], hist = [];
let settings = { myVol: 100 };
let cfg = { skip: 10, maxHist: 30, boost: [1, 1.5, 2, 3], sound3d: true };
let dragging = false;
let canControl = true;
let volPreview = null;       // الصوت وأنت تسحب الشريط (قبل ما يوصل للسيرفر)
let streamSeq = 0;

/* ================= أدوات ================= */
const thumb = (id) => `https://i.ytimg.com/vi/${id}/mqdefault.jpg`;
const fmt = (s) => {
  s = Math.max(0, Math.floor(s || 0));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60;
  return (h ? h + ':' + String(m).padStart(2, '0') : m) + ':' + String(x).padStart(2, '0');
};
const esc = (t) => String(t ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));

const stateOf = (plate) => (plate && sessions[plate] ? sessions[plate].state : null);
const cur = () => stateOf(focus);
const boostOf = (s) => cfg.boost[(s && s.boost ? s.boost : 1) - 1] || 1;

// مكان الأغنية المتوقع الحين (السيرفر يرسل المكان وقت الإرسال، ونضيف الوقت اللي مر)
function expectedPos(plate) {
  const ses = sessions[plate];
  if (!ses || !ses.state) return 0;
  const p = ses.state.pos || 0;
  return ses.state.playing ? p + (performance.now() - ses.at) / 1000 : p;
}

function parseLink(raw) {
  raw = (raw || '').trim();
  if (/^[\w-]{11}$/.test(raw)) return { id: raw, t: 0 };
  let u;
  try { u = new URL(raw.startsWith('http') ? raw : 'https://' + raw); } catch { return null; }
  const host = u.hostname.replace(/^(www\.|m\.|music\.)/, '');
  let id = null;
  if (host === 'youtu.be') id = u.pathname.slice(1, 12);
  else if (host === 'youtube.com' || host === 'youtube-nocookie.com') {
    id = u.searchParams.get('v');
    if (!id) {
      const m = u.pathname.match(/\/(shorts|embed|live|v)\/([\w-]{11})/);
      if (m) id = m[2];
    }
  }
  if (!id || !/^[\w-]{11}$/.test(id)) return null;
  // وقت البداية من الرابط ?t=90 أو t=1m30s
  let t = 0;
  const tp = u.searchParams.get('t') || u.searchParams.get('start');
  if (tp) {
    if (/^\d+$/.test(tp)) t = +tp;
    else {
      const m = tp.match(/(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?/);
      if (m) t = (+m[1] || 0) * 3600 + (+m[2] || 0) * 60 + (+m[3] || 0);
    }
  }
  return { id, t };
}

/* ================= التخزين (مفضلة + سجل + إعداداتي) ================= */
const save = (key) => post('store', { key, data: key === 'fav' ? fav : key === 'hist' ? hist : settings });
const isFav = (id) => fav.some((x) => x.id === id);

function toggleFav() {
  const s = cur();
  if (!s || !s.videoId) return;
  const id = s.videoId;
  if (isFav(id)) fav = fav.filter((x) => x.id !== id);
  else fav.unshift({ id, title: s.title || currentTitle() || id });
  save('fav'); renderFav(); renderNow();
}

function addHist(id, title) {
  hist = hist.filter((x) => x.id !== id);
  hist.unshift({ id, title: title || id, at: Date.now() });
  if (hist.length > cfg.maxHist) hist.length = cfg.maxHist;
  save('hist'); renderHist();
}

function updateTitle(id, title) {
  let changed = false;
  for (const arr of [hist, fav]) {
    const it = arr.find((x) => x.id === id);
    if (it && (!it.title || it.title === id)) { it.title = title; changed = true; }
  }
  if (changed) { save('hist'); save('fav'); renderHist(); renderFav(); }
}

/* ================= الرسم ================= */
function listHTML(arr, kind) {
  if (!arr.length) return `<div class="empty">${kind === 'fav' ? 'ما أضفت شي للمفضلة' : 'السجل فاضي'}</div>`;
  const s = cur();
  return arr.map((x) => `
    <div class="item ${s && s.videoId === x.id ? 'playing' : ''}" data-id="${esc(x.id)}" data-title="${esc(x.title)}">
      <img src="${thumb(esc(x.id))}" alt="">
      <div class="t">${esc(x.title)}${kind === 'hist' && x.at ? `<div class="m">${new Date(x.at).toLocaleString('ar-SA', { hour: '2-digit', minute: '2-digit', day: 'numeric', month: 'short' })}</div>` : ''}</div>
      <button class="x" data-del="${kind}">✕</button>
    </div>`).join('');
}
const renderFav = () => ($('favList').innerHTML = listHTML(fav, 'fav'));
const renderHist = () => ($('histList').innerHTML = listHTML(hist, 'hist'));

function currentTitle() {
  const st = streams.get(focus);
  try { return st && st.ready && st.player.getVideoData().title; } catch { return null; }
}

function renderBoost(s) {
  const lvl = s && s.boost ? s.boost : 1;
  const mult = cfg.boost[lvl - 1] || 1;
  const b = $('boostBtn');
  b.textContent = lvl > 1 ? `BOOST ×${mult}` : 'BOOST';
  b.classList.toggle('on', lvl > 1);
  b.classList.toggle('max', lvl >= cfg.boost.length && lvl > 1);
}

function renderNow() {
  const s = cur();
  const has = s && s.videoId;
  $('title').textContent = has ? (s.title || currentTitle() || 'جاري التحميل...') : 'ما فيه شي يشتغل';
  $('sub').textContent = has ? (s.playing ? 'يشتغل الآن' : 'متوقف') : 'CarPlay';
  $('toggle').textContent = has && s.playing ? '❚❚' : '▶';
  const c = $('cover');
  if (has) { c.style.backgroundImage = `url(${thumb(s.videoId)})`; c.classList.add('has'); }
  else { c.style.backgroundImage = ''; c.classList.remove('has'); }
  $('favBtn').textContent = has && isFav(s.videoId) ? '♥' : '♡';
  $('favBtn').classList.toggle('on', !!(has && isFav(s.videoId)));
  if (volPreview === null) {
    const v = s && typeof s.volume === 'number' ? s.volume : $('vol').value;
    $('vol').value = v; $('volPct').textContent = v + '%';
  }
  renderBoost(s);
  if (!has) { $('seek').value = 0; $('cur').textContent = '0:00'; $('dur').textContent = '0:00'; }
  document.querySelectorAll('.item').forEach((el) => el.classList.toggle('playing', !!has && el.dataset.id === s.videoId));
}

/* ================= مشغلات يوتيوب (واحد لكل سيارة تنسمع) ================= */
window.onYouTubeIframeAPIReady = () => { ytReady = true; pump(); };

function createStream(plate) {
  const holder = document.createElement('div');
  const el = document.createElement('div');
  el.id = 'yt-' + (++streamSeq);
  holder.appendChild(el);
  $('yt-wrap').appendChild(holder);

  const st = { plate, holder, ready: false, loadedId: null, vol: 0, applied: -1, unwantedSince: 0 };
  st.player = new YT.Player(el.id, {
    width: 200, height: 200,
    playerVars: { autoplay: 0, controls: 0, disablekb: 1, fs: 0, rel: 0, playsinline: 1, iv_load_policy: 3 },
    events: {
      onReady: () => {
        st.ready = true;
        st.player.setVolume(0);
        st.applied = 0;
        reconcile(plate);
      },
      onStateChange: (e) => {
        const s = stateOf(plate);
        if (e.data === YT.PlayerState.PLAYING) {
          if (plate === focus && s && s.videoId) {
            const t = currentTitle();
            if (t) {
              if (!s.title) s.title = t;
              post('title', { id: s.videoId, title: t, duration: Math.floor(st.player.getDuration() || 0) });
              updateTitle(s.videoId, t);
              renderNow();
            }
          }
          // لو السيرفر يقول متوقف والمشغل اشتغل (مثلاً بعد التحميل) نوقفه
          if (!s || !s.playing) st.player.pauseVideo();
        } else if (e.data === YT.PlayerState.ENDED) {
          if (s && s.playing) post('ended', { plate });
        }
      },
      onError: (e) => { if (plate === focus) post('error', { code: e.data }); },
    },
  });
  streams.set(plate, st);
  return st;
}

function destroyStream(plate) {
  const st = streams.get(plate);
  if (!st) return;
  try { st.player.destroy(); } catch {}
  st.holder.remove();
  streams.delete(plate);
}

// نخلي المشغل يطابق حالة السيرفر (الأغنية، المكان، تشغيل / إيقاف)
function reconcile(plate) {
  const st = streams.get(plate);
  if (!st || !st.ready) return;
  const s = stateOf(plate);
  const p = st.player;

  if (!s || !s.videoId) {
    st.loadedId = null;
    try { p.stopVideo(); } catch {}
    return;
  }

  const pos = expectedPos(plate);
  if (st.loadedId !== s.videoId) {
    st.loadedId = s.videoId;
    if (s.playing) p.loadVideoById({ videoId: s.videoId, startSeconds: pos });
    else p.cueVideoById({ videoId: s.videoId, startSeconds: pos });
    return;
  }

  const ps = p.getPlayerState();
  if (Math.abs((p.getCurrentTime() || 0) - pos) > 2.5) p.seekTo(pos, true);
  if (s.playing && ps !== YT.PlayerState.PLAYING && ps !== YT.PlayerState.BUFFERING) p.playVideo();
  if (!s.playing && ps === YT.PlayerState.PLAYING) p.pauseVideo();
}

// الصوت النهائي = صوت السيارة × البوست × قوة الـ 3D × صوتك أنت
function targetVolume(plate) {
  const s = stateOf(plate);
  if (!s || !s.playing) return 0;
  const g = mix[plate] || 0;
  const base = plate === focus && volPreview !== null ? volPreview : (s.volume ?? 50);
  return clamp(base * boostOf(s) * g * (settings.myVol / 100), 0, 100);
}

// يشتغل كل 100ms: ينشئ / يحذف المشغلات وينعّم الصوت (fade) عشان ما يقفز فجأة
function pump() {
  if (!ytReady) return;
  const t = performance.now();
  const wanted = new Set();
  const fs = cur();
  if (fs && fs.videoId) wanted.add(focus);
  for (const plate in mix) if (mix[plate] > 0 && stateOf(plate)) wanted.add(plate);

  for (const plate of wanted) {
    const st = streams.get(plate);
    if (!st) createStream(plate);
    else st.unwantedSince = 0;
  }

  for (const [plate, st] of streams) {
    if (!wanted.has(plate)) {
      if (!st.unwantedSince) st.unwantedSince = t;
      st.vol = 0;
      if (t - st.unwantedSince > 2000) { destroyStream(plate); continue; }
    }
    if (!st.ready) continue;
    const target = wanted.has(plate) ? targetVolume(plate) : 0;
    st.vol += (target - st.vol) * 0.3;
    if (Math.abs(target - st.vol) < 0.5) st.vol = target;
    const v = Math.round(st.vol);
    if (v !== st.applied) { st.applied = v; try { st.player.setVolume(v); } catch {} }
  }
}
setInterval(pump, 100);

// تصحيح الانحراف عن السيرفر كل شوي
setInterval(() => { for (const plate of streams.keys()) reconcile(plate); }, 5000);

// تحديث شريط الوقت
setInterval(() => {
  const st = streams.get(focus);
  const s = cur();
  if (!st || !st.ready || !s || !s.videoId || dragging) return;
  const d = st.player.getDuration() || 0, c = st.player.getCurrentTime() || 0;
  $('seek').max = Math.max(1, Math.floor(d));
  $('seek').value = Math.floor(c);
  $('cur').textContent = fmt(c);
  $('dur').textContent = fmt(d);
}, 500);

/* ================= حالة السيرفر ================= */
function setSession(plate, state, initial = false) {
  const prev = stateOf(plate);
  if (state) sessions[plate] = { state, at: performance.now() };
  else delete sessions[plate];

  if (!initial && plate === focus && state && state.videoId && (!prev || prev.videoId !== state.videoId)) {
    addHist(state.videoId, state.title);
  }
  if (plate === focus) volPreview = null;
  reconcile(plate);
}

/* ================= الأوامر ================= */
function play(id, title, startAt = 0) {
  post('play', { id, title: title && title !== id ? title : null, startAt });
}

function action(act) {
  const s = cur();
  if (!s || !s.videoId) return;
  switch (act) {
    case 'toggle': post('control', { action: s.playing ? 'pause' : 'resume' }); break;
    case 'back':   post('control', { action: 'skip', value: -cfg.skip }); break;
    case 'fwd':    post('control', { action: 'skip', value: cfg.skip }); break;
    case 'stop':   post('control', { action: 'stop' }); break;
    case 'fav':    toggleFav(); break;
    case 'boost': {
      const next = ((s.boost || 1) % cfg.boost.length) + 1;
      post('control', { action: 'boost', value: next });
      break;
    }
  }
}

/* ================= الأحداث ================= */
document.querySelectorAll('.tab').forEach((b) => b.addEventListener('click', () => {
  document.querySelectorAll('.tab').forEach((x) => x.classList.toggle('active', x === b));
  document.querySelectorAll('.page').forEach((p) => p.classList.toggle('active', p.id === 'tab-' + b.dataset.tab));
}));

document.querySelectorAll('[data-act]').forEach((b) => b.addEventListener('click', () => action(b.dataset.act)));

$('linkForm').addEventListener('submit', (e) => {
  e.preventDefault();
  const r = parseLink($('link').value);
  if (!r) return post('notify', { msg: 'الرابط غير صحيح' });
  $('link').value = '';
  play(r.id, null, r.t);
});

$('seek').addEventListener('input', () => { dragging = true; $('cur').textContent = fmt($('seek').value); });
$('seek').addEventListener('change', () => {
  dragging = false;
  post('control', { action: 'seek', value: +$('seek').value });
});

// صوت السيارة: تسمع التغيير فوراً وأنت تسحب، وينرسل للسيرفر لما تفلت
$('vol').addEventListener('input', () => { volPreview = +$('vol').value; $('volPct').textContent = volPreview + '%'; });
$('vol').addEventListener('change', () => post('control', { action: 'volume', value: +$('vol').value }));

// صوتك أنت: محفوظ عندك وما يأثر على غيرك
$('myVol').addEventListener('input', () => { settings.myVol = +$('myVol').value; $('myVolPct').textContent = settings.myVol + '%'; });
$('myVol').addEventListener('change', () => save('settings'));

for (const listId of ['favList', 'histList']) {
  $(listId).addEventListener('click', (e) => {
    const item = e.target.closest('.item');
    if (!item) return;
    const del = e.target.closest('[data-del]');
    if (del) {
      e.stopPropagation();
      if (del.dataset.del === 'fav') { fav = fav.filter((x) => x.id !== item.dataset.id); save('fav'); renderFav(); renderNow(); }
      else { hist = hist.filter((x) => x.id !== item.dataset.id); save('hist'); renderHist(); }
      return;
    }
    play(item.dataset.id, item.dataset.title);
  });
}

$('close').addEventListener('click', () => post('close'));
document.addEventListener('keydown', (e) => {
  if ($('app').classList.contains('hidden')) return;
  if (e.key === 'Escape') return post('close');
  // مسافة = تشغيل / إيقاف (إلا لو تكتب بخانة الرابط)
  if (e.code === 'Space' && e.target.id !== 'link' && canControl) { e.preventDefault(); action('toggle'); }
});

const tick = () => { const d = new Date(); $('clock').textContent = String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0'); };
tick(); setInterval(tick, 10000);

function setPerm(cc) {
  canControl = cc !== false;
  document.querySelector('main').classList.toggle('locked', !canControl);
  $('note').classList.toggle('hidden', canControl);
}

/* ================= رسائل اللعبة ================= */
window.addEventListener('message', (e) => {
  const d = e.data || {};
  switch (d.action) {
    case 'open':
      setPerm(d.canControl);
      $('app').classList.remove('hidden');
      renderNow();
      break;
    case 'perm':
      setPerm(d.canControl);
      break;
    case 'close':
      $('app').classList.add('hidden');
      break;
    case 'focus':
      focus = d.plate || null;
      volPreview = null;
      renderNow(); renderFav(); renderHist();
      pump();
      break;
    case 'sync':
      setSession(d.plate, d.state);
      renderNow();
      break;
    case 'syncAll':
      for (const k of Object.keys(sessions)) delete sessions[k];
      if (d.focus !== undefined) focus = d.focus || null;
      for (const [plate, state] of Object.entries(d.states || {})) setSession(plate, state, true);
      for (const plate of streams.keys()) reconcile(plate);
      renderNow();
      break;
    case 'mix':
      mix = d.mix && !Array.isArray(d.mix) ? d.mix : {};
      break;
  }
});

post('ready').then((r) => {
  if (!r) return;
  fav = Array.isArray(r.fav) ? r.fav : [];
  hist = Array.isArray(r.hist) ? r.hist : [];
  if (r.settings && typeof r.settings.myVol === 'number') settings.myVol = clamp(r.settings.myVol, 0, 100);
  if (r.cfg) cfg = { ...cfg, ...r.cfg };
  if (!Array.isArray(cfg.boost) || !cfg.boost.length) cfg.boost = [1];
  $('backBtn').textContent = '−' + cfg.skip;
  $('fwdBtn').textContent = '+' + cfg.skip;
  $('myVol').value = settings.myVol; $('myVolPct').textContent = settings.myVol + '%';
  $('badge3d').classList.toggle('hidden', !cfg.sound3d);
  if (cfg.boost.length < 2) $('boostBtn').classList.add('hidden');
  renderFav(); renderHist(); renderNow();
});
