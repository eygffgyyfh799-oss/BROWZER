'use strict';
/* ════════════════════════════════════════════════════════════════════════════
   RespectJustice - واجهة نظام معلومات المواطنين
   كل النصوص تنضاف كنص (textContent) وليس HTML: ما يمكن حقن كود من البيانات
   ════════════════════════════════════════════════════════════════════════════ */

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'RespectJustice';
const $ = (id) => document.getElementById(id);

const S = {
    open: false,
    info: {},
    perms: {},
    me: {},
    config: {},
    stack: [],
    current: null,
    busy: 0,
};

// ═════ أدوات DOM ═════
function h(tag, props, ...kids) {
    const el = document.createElement(tag);
    if (props) {
        for (const [k, v] of Object.entries(props)) {
            if (v == null || v === false) continue;
            if (k === 'class') el.className = v;
            else if (k === 'style') el.style.cssText = v;
            else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2), v);
            else if (k === 'value') el.value = v;
            else el.setAttribute(k, v === true ? '' : v);
        }
    }
    for (const kid of kids.flat(Infinity)) {
        if (kid == null || kid === false) continue;
        el.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
    }
    return el;
}

// القوائم من Lua: القائمة الفاضية ممكن توصل {} بدل [] - هذي تضمن إنها دايماً مصفوفة
const arr = (x) => (Array.isArray(x) ? x : x && typeof x === 'object' ? Object.values(x) : []);
const val = (v) => (v === null || v === undefined || v === '' ? '-' : String(v));
const money = (n) => {
    const x = Math.floor(Number(n) || 0);
    return (x < 0 ? '-$' : '$') + Math.abs(x).toLocaleString('en-US');
};
const gender = (g) => (Number(g) === 0 ? 'ذكر' : Number(g) === 1 ? 'أنثى' : '-');
const dot = (online) => (online ? '🟢' : '⚫');

// ═════ الاتصال بـ Lua ═════
async function nui(endpoint, data) {
    try {
        const res = await fetch(`https://${RES}/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        });
        return await res.json();
    } catch (e) {
        return { ok: false, err: 'تعذر الاتصال' };
    }
}

function setBusy(delta) {
    S.busy = Math.max(0, S.busy + delta);
    $('loader').classList.toggle('on', S.busy > 0);
}

async function call(name, ...args) {
    setBusy(1);
    const res = await nui('call', { name, args });
    setBusy(-1);
    if (!res || res.ok === false) {
        toast((res && res.err) || 'حدث خطأ', 'error');
        return null;
    }
    if (res.perms) S.perms = res.perms;
    return res;
}

// ═════ إشعارات ═════
function toast(text, type = 'info', ms = 4000) {
    const el = h('div', { class: `toast ${type}` }, text);
    $('toasts').append(el);
    setTimeout(() => el.remove(), ms);
}

// ═════ نوافذ الإدخال والتأكيد ═════
function closeModal() {
    const finish = S.modalFinish;
    S.modalFinish = null;
    $('modal-root').replaceChildren();
    if (finish) finish(null);
}

function modal({ title, text, fields = [], okText = 'تأكيد', danger = false }) {
    return new Promise((resolve) => {
        const inputs = {};
        const body = h('div', { class: 'modal-body' });
        if (text) body.append(h('p', null, text));

        for (const f of fields) {
            let input;
            if (f.type === 'textarea') {
                input = h('textarea', { maxlength: f.max, placeholder: f.placeholder || '' });
            } else if (f.type === 'select') {
                input = h('select', null, (f.options || []).map((o) => h('option', { value: String(o.value) }, o.label)));
            } else {
                input = h('input', { type: f.type === 'number' ? 'number' : 'text', maxlength: f.max, min: f.min, placeholder: f.placeholder || '' });
            }
            if (f.value !== undefined && f.value !== null) input.value = String(f.value);
            inputs[f.name] = { input, field: f };
            body.append(h('div', { class: 'field' }, h('label', null, f.label + (f.required ? ' *' : '')), input, f.hint ? h('div', { class: 'hint' }, f.hint) : null));
        }

        let done = false;
        const finish = (result) => {
            if (done) return;
            done = true;
            S.modalFinish = null;
            $('modal-root').replaceChildren();
            resolve(result);
        };
        const submit = () => {
            const out = {};
            for (const [name, { input, field }] of Object.entries(inputs)) {
                let v = input.value.trim();
                if (field.required && v === '') { input.focus(); toast(`${field.label} مطلوب`, 'error'); return; }
                if (field.type === 'number') {
                    v = v === '' ? null : Number(v);
                    if (v !== null && (!Number.isFinite(v) || (field.min != null && v < field.min))) { input.focus(); toast(`${field.label} غير صحيح`, 'error'); return; }
                    if (v !== null && field.maxValue != null && v > field.maxValue) { input.focus(); toast(`${field.label}: الحد الأقصى ${field.maxValue.toLocaleString('en-US')}`, 'error'); return; }
                }
                out[name] = v;
            }
            finish(fields.length ? out : true);
        };

        const back = h('div', { class: 'modal-back', onclick: (e) => { if (e.target === back) finish(null); } },
            h('div', { class: 'modal' },
                h('div', { class: 'modal-head' }, title),
                body,
                h('div', { class: 'modal-foot' },
                    h('button', { class: danger ? 'btn red' : 'btn primary', onclick: submit }, okText),
                    h('button', { class: 'btn', onclick: () => finish(null) }, 'إلغاء'),
                ),
            ),
        );
        back.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' && e.target.tagName !== 'TEXTAREA') submit();
        });
        closeModal();
        S.modalFinish = finish;
        $('modal-root').replaceChildren(back);
        const first = Object.values(inputs)[0];
        if (first) setTimeout(() => first.input.focus(), 30);
    });
}

const confirmBox = (title, text, danger) => modal({ title, text, danger, okText: danger ? 'نعم، متأكد' : 'تأكيد' });

// ═════ عناصر جاهزة ═════
function empty(text, icon = '📭') {
    return h('div', { class: 'empty' }, h('div', { class: 'big' }, icon), text);
}

function item({ icon, title, sub, side, onclick }) {
    return h('div', { class: 'item' + (onclick ? ' clickable' : ''), onclick },
        icon ? h('div', { class: 'item-icon' }, icon) : null,
        h('div', { class: 'item-body' }, h('div', { class: 'item-title' }, title), sub ? h('div', { class: 'item-sub' }, sub) : null),
        side ? h('div', { class: 'item-side', onclick: (e) => e.stopPropagation() }, side) : null,
    );
}

function stat(label, value, tone, onclick) {
    return h('div', { class: 'stat' + (onclick ? ' clickable' : ''), style: tone ? `--tone: var(--${tone})` : null, onclick },
        h('div', { class: 'label' }, label), h('div', { class: 'value' }, value));
}

function card(title, ...body) {
    return h('div', { class: 'card' }, title ? h('div', { class: 'card-title' }, title) : null, ...body);
}

function kv(pairs) {
    return h('div', { class: 'kv' }, pairs.map(([k, v]) => h('div', null, h('div', { class: 'k' }, k), h('div', { class: 'v' }, val(v)))));
}

function badge(text, color) {
    return h('span', { class: `badge ${color || ''}` }, text);
}

function btn(text, onclick, cls = '') {
    return h('button', { class: `btn ${cls}`, onclick }, text);
}

function citizenItem(c) {
    return item({
        icon: c.suspended ? '⛔' : dot(c.online),
        title: `${c.serverId ? `[${c.serverId}] ` : ''}${c.name || 'بدون اسم'}`,
        sub: `${c.status ? c.status.text : ''}\nالرقم الوطني: ${c.citizenid} | ${val(c.job)} | الجوال: ${val(c.phone)}`,
        side: c.suspended ? badge('خدماته موقوفة', 'red') : null,
        onclick: () => go('profile', c.citizenid),
    });
}

function pager(page, pages, onPage) {
    if (pages <= 1) return null;
    return h('div', { class: 'pager' },
        h('button', { class: 'btn small', disabled: page <= 0 || null, onclick: () => onPage(page - 1) }, '→ السابق'),
        `صفحة ${page + 1} من ${pages}`,
        h('button', { class: 'btn small', disabled: page + 1 >= pages || null, onclick: () => onPage(page + 1) }, 'التالي ←'),
    );
}

// ═════ التنقل ═════
const NAV = [
    { page: 'home', icon: '🏠', label: 'الرئيسية' },
    { page: 'online', icon: '🟢', label: 'المتصلين' },
    { page: 'citizens', icon: '👥', label: 'جميع المواطنين' },
    { page: 'search', icon: '🔎', label: 'البحث' },
    { page: 'reports', icon: '⚖️', label: 'القضايا', perm: 'reports', badge: () => S.info.newReports },
    { page: 'jobs', icon: '🏢', label: 'القطاعات' },
    { page: 'city', icon: '🏙️', label: 'المدينة', perm: 'city' },
    { page: 'summons', icon: '📜', label: 'الاستدعاءات', perm: 'summon' },
    { page: 'suspended', icon: '⛔', label: 'الموقوفين', badge: () => S.info.suspended },
    { page: 'logs', icon: '🗂️', label: 'سجل العمليات', perm: 'logs' },
];

function renderNav() {
    const root = S.stack.length ? S.stack[0].page : 'home';
    const active = S.current ? S.current.page : 'home';
    $('nav').replaceChildren(...NAV.filter((n) => !n.perm || S.perms[n.perm]).map((n) => {
        const count = n.badge ? Number(n.badge()) || 0 : 0;
        return h('button', {
            class: active === n.page || (root === n.page && !NAV.some((x) => x.page === active)) ? 'active' : '',
            onclick: () => go(n.page, undefined, true),
        }, h('span', { class: 'nav-icon' }, n.icon), n.label, count > 0 ? h('span', { class: 'nav-badge' }, count) : null);
    }));
}

async function go(page, arg, reset) {
    S.logsPage = 0;
    if (reset) S.stack = [];
    else if (S.current) S.stack.push(S.current);
    S.current = { page, arg };
    await render();
}

async function back() {
    if (!S.stack.length) return;
    S.current = S.stack.pop();
    await render();
}

async function render() {
    const { page, arg } = S.current;
    const def = PAGES[page];
    if (!def) return;
    $('page-title').textContent = typeof def.title === 'function' ? def.title(arg) : def.title;
    $('btn-back').disabled = S.stack.length === 0;
    renderNav();
    const content = $('content');
    const token = Symbol('render');
    S.renderToken = token;
    let node;
    try {
        node = await def.render(arg);
    } catch (e) {
        console.error(e);
        node = empty('حدث خطأ في عرض الصفحة', '⚠️');
    }
    if (S.renderToken !== token) return; // صفحة ثانية انفتحت أثناء التحميل
    content.replaceChildren(node || empty('تعذر تحميل البيانات', '⚠️'));
    content.scrollTop = 0;
    renderNav();
}

const refresh = () => render();

// ═════ الصفحات ═════
const PAGES = {};

PAGES.home = {
    title: 'الرئيسية',
    async render() {
        const info = await call('panelInfo');
        if (!info) return null;
        S.info = info;
        const quick = h('input', { placeholder: 'بحث سريع: الاسم / الرقم الوطني / الجوال / رقم السيرفر' });
        quick.addEventListener('keydown', (e) => { if (e.key === 'Enter' && quick.value.trim()) go('search', quick.value.trim()); });

        return h('div', null,
            h('div', { class: 'grid stats' },
                stat('المتصلين الآن', info.online, 'green', () => go('online')),
                stat('المواطنين', info.totalCitizens, 'gold', () => go('citizens')),
                stat('العدل في الدوام', info.justiceOnDuty, 'blue', () => go('jobs')),
                S.perms.reports ? stat('قضايا جديدة', info.newReports, 'yellow', () => go('reports')) : null,
                stat('خدمات موقوفة', info.suspended, 'red', () => go('suspended')),
            ),
            h('div', { style: 'height:14px' }),
            card('🔎 بحث سريع', h('div', { class: 'searchbar' }, quick, btn('بحث', () => quick.value.trim() && go('search', quick.value.trim()), 'primary'))),
            card('⚡ اختصارات', h('div', { class: 'actions' },
                btn('🟢 المتصلين', () => go('online')),
                btn('👥 جميع المواطنين', () => go('citizens')),
                S.perms.reports ? btn('⚖️ القضايا', () => go('reports')) : null,
                btn('🏢 القطاعات', () => go('jobs')),
                S.perms.city ? btn('🏙️ المدينة', () => go('city')) : null,
                S.perms.logs ? btn('🗂️ سجل العمليات', () => go('logs')) : null,
            )),
        );
    },
};

PAGES.online = {
    title: 'اللاعبين المتصلين',
    async render() {
        const res = await call('getOnlinePlayers');
        if (!res) return null;
        return card(`🟢 المتصلين الآن (${arr(res.players).length})`,
            arr(res.players).length ? h('div', { class: 'list' }, arr(res.players).map(citizenItem)) : empty('لا يوجد لاعبين'));
    },
};

PAGES.citizens = {
    title: 'جميع المواطنين',
    async render(arg) {
        const state = arg || { page: 0, filter: 'all' };
        const res = await call('getAllCitizens', state.page, state.filter);
        if (!res) return null;
        const set = (patch) => { S.current.arg = { ...state, ...patch }; render(); };
        const chip = (f, label) => h('button', { class: 'chip' + (res.filter === f ? ' active' : ''), onclick: () => set({ filter: f, page: 0 }) }, label);
        return h('div', null,
            h('div', { class: 'chips' }, chip('all', `الكل`), chip('online', `🟢 المتصلين (${res.online})`), chip('offline', '⚫ غير المتصلين')),
            card(`👥 ${res.total} مواطن`,
                arr(res.list).length ? h('div', { class: 'list' }, arr(res.list).map(citizenItem)) : empty('لا يوجد مواطنين'),
                pager(res.page, res.pages, (p) => set({ page: p })),
            ),
        );
    },
};

PAGES.search = {
    title: 'البحث عن مواطن',
    async render(query) {
        const input = h('input', { placeholder: 'الاسم / الرقم الوطني / الجوال / رقم السيرفر', value: query || '' });
        const doSearch = () => { const q = input.value.trim(); if (q) { S.current.arg = q; render(); } };
        input.addEventListener('keydown', (e) => { if (e.key === 'Enter') doSearch(); });
        setTimeout(() => input.focus(), 50);

        let results = null;
        if (query) {
            const res = await call('searchCitizens', query);
            results = res ? card(`النتائج (${arr(res.results).length})`, arr(res.results).length ? h('div', { class: 'list' }, arr(res.results).map(citizenItem)) : empty('لا توجد نتائج', '🔍')) : null;
        }
        return h('div', null, h('div', { class: 'searchbar' }, input, btn('بحث', doSearch, 'primary')), results || empty('اكتب في خانة البحث (يشمل غير المتصلين)', '🔎'));
    },
};

PAGES.suspended = {
    title: 'الموقوفة خدماتهم',
    async render() {
        const res = await call('getSuspended');
        if (!res) return null;
        return card(`⛔ الموقوفين (${arr(res.list).length})`, arr(res.list).length ? h('div', { class: 'list' }, arr(res.list).map((s) => item({
            icon: '⛔',
            title: `${s.status && s.status.online ? '🟢 ' : ''}${s.name} (${s.citizenid})`,
            sub: `السبب: ${val(s.reason)}\nبواسطة ${val(s.officer)} - ${val(s.date)}`,
            onclick: () => go('profile', s.citizenid),
        }))) : empty('لا يوجد مواطنين موقوفين', '✅'));
    },
};

// ═════ ملف المواطن ═════
PAGES.profile = {
    title: (cid) => `ملف المواطن ${cid}`,
    async render(cid) {
        const res = await call('getProfile', cid);
        if (!res) return null;
        const p = res.profile;
        const perms = res.perms || {};
        const tab = (S.profileTab && S.profileTab.cid === cid) ? S.profileTab.tab : 'personal';
        const reload = () => render();

        const head = h('div', { class: 'profile-head' },
            h('div', { class: 'avatar' }, (p.firstname || '?').slice(0, 1)),
            h('div', { style: 'flex:1;min-width:0' },
                h('div', { class: 'profile-name' }, p.name || 'بدون اسم'),
                h('div', { class: 'profile-meta' },
                    badge(p.status ? p.status.text : (p.online ? 'متصل' : 'غير متصل'), p.online ? 'green' : 'gray'),
                    badge(`الرقم الوطني: ${p.citizenid}`),
                    badge(`${val(p.job.label)} - ${val(p.job.grade)}`, 'blue'),
                    p.gang ? badge(`🎭 ${p.gang.label}`, 'yellow') : null,
                    p.online ? badge(`البنق ${val(p.ping)}ms`, 'gray') : null,
                ),
            ),
        );

        const alert = p.suspension ? h('div', { class: 'alert red' }, `⛔ الخدمات موقوفة: ${val(p.suspension.reason)} (بواسطة ${val(p.suspension.officer)} - ${val(p.suspension.date)})`) : null;

        const actions = h('div', { class: 'actions', style: 'margin-bottom:14px' }, profileActions(p, perms, reload));

        const tabs = [
            ['personal', '🪪 البيانات'], ['money', '💰 المالية'], ['job', '💼 الوظيفة والسجل'],
            ['licenses', '📄 التراخيص'], ['vehicles', `🚗 المركبات${p.vehicles ? ` (${arr(p.vehicles).length})` : ''}`],
            ['houses', `🏠 العقارات${p.houses ? ` (${arr(p.houses).length})` : ''}`], ['items', `📦 الممتلكات (${arr(p.items).length})`],
            ['reports', `⚖️ القضايا (${arr(p.reports).length})`], ['summons', `📜 الاستدعاءات (${arr(p.summons).length})`],
            perms.logs ? ['logs', '🗂️ السجل'] : null,
        ].filter(Boolean);

        const tabBar = h('div', { class: 'tabs' }, tabs.map(([key, label]) => h('button', {
            class: 'tab' + (tab === key ? ' active' : ''),
            onclick: () => { S.profileTab = { cid, tab: key }; render(); },
        }, label)));

        const body = await profileTab(tab, p, perms, reload);
        return h('div', null, head, alert, actions, tabBar, body);
    },
};

function profileActions(p, perms, reload) {
    const list = [];
    const self = p.isSelf;

    if (perms.locate) list.push(btn('📍 تحديد الموقع', async () => {
        const r = await call('locateCitizen', p.citizenid);
        if (r) toast(`${r.name} موجود في: ${val(r.street)}${r.inVehicle ? ' (داخل مركبة)' : ''} - تم وضع علامة على الخريطة`, 'success', 7000);
    }, 'blue'));

    if (perms.summon) list.push(btn('📜 استدعاء', async () => {
        const v = await modal({ title: `استدعاء ${p.name} للمحكمة`, okText: 'إرسال', fields: [
            { name: 'reason', label: 'السبب', required: true, max: S.config.summonMax || 200 },
            { name: 'appointment', label: 'الموعد', placeholder: 'مثال: الخميس 9 مساءً', max: 100 },
            { name: 'location', label: 'المكان', placeholder: 'مثال: قاعة المحكمة الرئيسية', max: 100 },
        ] });
        if (!v) return;
        const r = await call('sendSummon', p.citizenid, v.reason, v.appointment || '', v.location || '');
        if (r) { toast(r.delivered ? 'تم إرسال الاستدعاء ووصله الآن' : 'تم الحفظ، يوصله أول ما يدخل', 'success'); reload(); }
    }));

    if (!self && perms.withdraw) list.push(btn('💸 سحب من البنك', async () => {
        const maxValue = Math.min(S.config.withdrawMax || 5000000, Math.max(0, p.money.bank));
        const v = await modal({ title: `سحب من حساب ${p.name}`, text: `الرصيد الحالي: ${money(p.money.bank)}`, okText: 'متابعة', fields: [
            { name: 'amount', label: 'المبلغ', type: 'number', required: true, min: 1, maxValue },
            { name: 'reason', label: 'السبب', required: true, max: 200 },
        ] });
        if (!v || !await confirmBox('تأكيد السحب', `سحب ${money(v.amount)} من ${p.name}\nالسبب: ${v.reason}`, true)) return;
        const r = await call('withdrawBank', p.citizenid, v.amount, v.reason);
        if (r) { toast(`تم السحب، الرصيد الجديد: ${money(r.newBalance)}`, 'success'); reload(); }
    }, 'red'));

    if (!self && perms.compensation && p.online) list.push(btn('🤝 تعويض', async () => {
        const v = await modal({ title: `تعويض ${p.name}`, text: `يجب أن يكون بالقرب منك (${S.config.compensationDistance || 5} متر)`, fields: [
            { name: 'amount', label: 'المبلغ', type: 'number', required: true, min: 1, maxValue: S.config.compensationMax },
        ] });
        if (!v) return;
        await nui('compensate', { citizenid: p.citizenid, amount: v.amount });
        setTimeout(reload, 800);
    }, 'green'));

    if (!self && perms.suspend) {
        if (p.suspension) list.push(btn('🔓 رفع الإيقاف', async () => {
            if (!await confirmBox('رفع إيقاف الخدمات', `رفع إيقاف خدمات ${p.name}؟`)) return;
            if (await call('unsuspendCitizen', p.citizenid)) { toast('تم رفع الإيقاف', 'success'); reload(); }
        }, 'green'));
        else list.push(btn('⛔ إيقاف الخدمات', async () => {
            const v = await modal({ title: `إيقاف خدمات ${p.name}`, okText: 'إيقاف', danger: true, fields: [{ name: 'reason', label: 'السبب', required: true, max: 200 }] });
            if (v && await call('suspendCitizen', p.citizenid, v.reason)) { toast('تم إيقاف الخدمات', 'success'); reload(); }
        }, 'red'));
    }

    if (!self && perms.jobs) list.push(btn('💼 الوظيفة والرتبة', async () => { if (await changeJob(p.citizenid, p.name)) reload(); }, 'blue'));
    if (!self && perms.jobs && p.job.name !== S.config.unemployed) list.push(btn('❌ فصل', async () => { if (await fire(p.citizenid, p.name)) reload(); }, 'red'));
    if (!self && perms.gangs) list.push(btn('🎭 العصابة', async () => { if (await changeGang(p.citizenid, p.name)) reload(); }));

    if (!self && perms.edit) list.push(btn('✏️ تعديل البيانات', async () => {
        const v = await modal({ title: `تعديل بيانات ${p.name}`, okText: 'حفظ', fields: [
            { name: 'firstname', label: 'الاسم الأول', required: true, value: p.firstname, max: 20 },
            { name: 'lastname', label: 'اسم العائلة', required: true, value: p.lastname, max: 20 },
            { name: 'birthdate', label: 'تاريخ الميلاد', required: true, value: p.birthdate, max: 10, placeholder: 'YYYY-MM-DD' },
            { name: 'gender', label: 'الجنس', type: 'select', value: p.gender === 1 ? '1' : '0', options: [{ value: '0', label: 'ذكر' }, { value: '1', label: 'أنثى' }] },
            { name: 'nationality', label: 'الجنسية', required: true, value: p.nationality, max: 30 },
        ] });
        if (!v) return;
        v.gender = Number(v.gender);
        if (await call('editCitizen', p.citizenid, v)) { toast('تم تحديث البيانات', 'success'); reload(); }
    }));

    return list;
}

async function profileTab(tab, p, perms, reload) {
    const i = p.info || {};
    switch (tab) {
        case 'personal':
            return card(null, kv([
                ['الاسم الكامل', p.name], ['الرقم الوطني', p.citizenid], ['تاريخ الميلاد', p.birthdate], ['الجنس', gender(p.gender)],
                ['الجنسية', p.nationality], ['رقم الجوال', p.phone], ['رقم الحساب', p.account], ['فصيلة الدم', i.bloodtype],
                ['البصمة', i.fingerprint], ['رقم المحفظة', i.walletid], ['آخر حفظ للبيانات', p.lastUpdated],
            ]));
        case 'money':
            return h('div', null,
                h('div', { class: 'grid stats', style: 'margin-bottom:14px' },
                    stat('رصيد البنك', money(p.money.bank), 'green'), stat('الكاش', money(p.money.cash), 'gold'),
                    p.money.crypto != null ? stat('الكريبتو', val(p.money.crypto), 'purple') : null),
                card('عمليات وزارة العدل', (p.transactions || []).length ? h('div', { class: 'list' }, arr(p.transactions).map((t) => item({
                    icon: t.type === 'withdraw' ? '🔻' : '🔺',
                    title: `${t.type === 'withdraw' ? 'سحب' : 'تعويض'} ${money(t.amount)}`,
                    sub: `${val(t.reason)}\nبواسطة ${val(t.officer)} - ${val(t.date)}`,
                }))) : empty('لا توجد عمليات')));
        case 'job':
            return card(null, kv([
                ['الوظيفة', `${val(p.job.label)} - ${val(p.job.grade)}`], ['الدوام', p.job.onduty ? 'في الدوام' : 'خارج الدوام'],
                ['مدير', p.job.isboss ? 'نعم' : 'لا'], ['العصابة', p.gang ? `${p.gang.label} - ${val(p.gang.grade)}` : 'لا يوجد'],
                ['السجن', i.injail > 0 ? `مسجون (${i.injail} شهر)` : 'غير مسجون'],
                ['السجل الجنائي', i.criminalRecord ? `يوجد سجل${i.criminalRecordDate ? ' - ' + i.criminalRecordDate : ''}` : 'نظيف'],
                ['الحالة الصحية', i.isdead ? 'ميت / مصاب' : 'سليم'], ['رمز النداء', i.callsign],
            ]));
        case 'licenses': {
            const canToggle = perms.licenses && !p.isSelf;
            return card(null, (p.licenses || []).length ? h('div', { class: 'list' }, arr(p.licenses).map((l) => item({
                icon: l.active ? '✅' : '❌',
                title: l.label,
                sub: l.active ? 'فعالة' : 'غير فعالة',
                side: canToggle ? btn(l.active ? 'سحب' : 'منح', async () => {
                    if (!await confirmBox(`${l.active ? 'سحب' : 'منح'} ترخيص`, `${l.active ? 'سحب' : 'منح'} ${l.label} للمواطن ${p.name}؟`, l.active)) return;
                    if (await call('setLicense', p.citizenid, l.key, !l.active)) { toast('تم', 'success'); reload(); }
                }, `small ${l.active ? 'red' : 'green'}`) : null,
            }))) : empty('لا توجد تراخيص'));
        }
        case 'vehicles':
            if (!p.vehicles) return empty('جدول المركبات غير مفعل');
            return card(null, arr(p.vehicles).length ? h('div', { class: 'list' }, arr(p.vehicles).map((v) => item({
                icon: '🚗', title: `${v.label} | ${val(v.plate)}`,
                sub: `${v.state} | الكراج: ${val(v.garage)} | الوقود ${val(v.fuel)}% | المحرك ${val(v.engine)}% | الهيكل ${val(v.body)}%`,
                onclick: perms.city && v.plate ? () => go('vehicle', v.plate) : null,
            }))) : empty('لا توجد مركبات', '🚗'));
        case 'houses':
            if (!p.houses) return empty('جدول العقارات غير مفعل');
            return card(null, arr(p.houses).length ? h('div', { class: 'list' }, arr(p.houses).map((x) => item({ icon: '🏠', title: x.label }))) : empty('لا توجد عقارات', '🏠'));
        case 'items':
            return card(null, arr(p.items).length ? h('div', { class: 'list' }, arr(p.items).map((x) => item({ icon: '📦', title: x.label, side: badge(`× ${x.amount}`) }))) : empty('لا توجد ممتلكات', '📦'));
        case 'reports':
            return card(null, arr(p.reports).length ? h('div', { class: 'list' }, arr(p.reports).map((r) => item({
                icon: '⚖️', title: `#${r.id} | ${r.title}`, sub: `${r.role} | ${val(r.caseType)} | ${val(r.status)} | ${val(r.date)}`,
                onclick: perms.reports ? () => go('report', r.id) : null,
            }))) : empty('لا توجد قضايا', '⚖️'));
        case 'summons':
            return card(null, arr(p.summons).length ? h('div', { class: 'list' }, arr(p.summons).map((s) => summonItem(s, reload))) : empty('لا توجد استدعاءات', '📜'));
        case 'logs':
            return logsView(p.citizenid, S.logsPage || 0, reload);
    }
    return null;
}

function summonItem(s, reload) {
    const open = s.status === 'pending' || s.status === 'delivered';
    return item({
        icon: '📜',
        title: `#${s.id}${s.name ? ' | ' + s.name : ''} | ${s.statusLabel}`,
        sub: `${s.reason}\nالموعد: ${val(s.appointment)} | المكان: ${val(s.location)}\nبواسطة ${val(s.officer)} - ${val(s.date)}`,
        side: [
            s.citizenid ? btn('الملف', () => go('profile', s.citizenid), 'small') : null,
            open && S.perms.summon ? btn('تحديث', async () => {
                const v = await modal({ title: `تحديث الاستدعاء #${s.id}`, fields: [{ name: 'status', label: 'الحالة', type: 'select', options: [
                    { value: 'attended', label: 'حضر' }, { value: 'absent', label: 'لم يحضر' }, { value: 'cancelled', label: 'إلغاء الاستدعاء' }] }] });
                if (v && await call('setSummonStatus', s.id, v.status)) { toast('تم تحديث الاستدعاء', 'success'); reload(); }
            }, 'small') : null,
            S.perms.delete ? btn('حذف', async () => {
                if (await confirmBox('حذف الاستدعاء', `حذف الاستدعاء #${s.id} نهائياً؟`, true) && await call('deleteSummon', s.id)) { toast('تم الحذف', 'success'); reload(); }
            }, 'small red') : null,
        ],
    });
}

// ═════ الوظائف والعصابات ═════
async function pickGrade(title, grades, current) {
    grades = arr(grades);
    if (!grades.length) { toast('لا توجد رتب', 'error'); return null; }
    const v = await modal({ title, fields: [{ name: 'level', label: 'الرتبة', type: 'select', value: current != null ? String(current) : String(grades[0].level),
        options: grades.map((g) => ({ value: g.level, label: `${g.level} - ${g.name}${g.isboss ? ' (مدير)' : ''}` })) }] });
    return v ? Number(v.level) : null;
}

async function changeJob(cid, name, presetJob) {
    const res = await call('getJobs');
    if (!res) return false;
    let job = presetJob ? arr(res.jobs).find((j) => j.name === presetJob) : null;
    if (!job) {
        const v = await modal({ title: `وظيفة ${name}`, okText: 'التالي', fields: [{ name: 'job', label: 'القطاع', type: 'select',
            options: arr(res.jobs).map((j, i) => ({ value: i, label: `${j.label} (${j.name})` })) }] });
        if (!v) return false;
        job = arr(res.jobs)[Number(v.job)];
    }
    const level = await pickGrade(`الرتبة في ${job.label}`, arr(job.grades));
    if (level == null) return false;
    const grade = arr(job.grades).find((g) => g.level === level);
    if (!await confirmBox('تأكيد', `تعيين ${name} في ${job.label} برتبة ${grade ? grade.name : level}؟`)) return false;
    const r = await call('setCitizenJob', cid, job.name, level);
    if (r) toast(`تم التعيين: ${r.newJob}`, 'success');
    return !!r;
}

async function fire(cid, name) {
    if (!await confirmBox('فصل من الوظيفة', `فصل ${name} من وظيفته؟`, true)) return false;
    const r = await call('setCitizenJob', cid, S.config.unemployed, 0);
    if (r) toast('تم الفصل', 'success');
    return !!r;
}

async function changeGang(cid, name) {
    const res = await call('getGangs');
    if (!res) return false;
    const v = await modal({ title: `عصابة ${name}`, okText: 'التالي', fields: [{ name: 'gang', label: 'العصابة', type: 'select',
        options: arr(res.gangs).map((g, i) => ({ value: i, label: `${g.label} (${g.name})` })) }] });
    if (!v) return false;
    const gang = arr(res.gangs)[Number(v.gang)];
    const level = await pickGrade(`الرتبة في ${gang.label}`, arr(gang.grades));
    if (level == null) return false;
    const r = await call('setGang', cid, gang.name, level);
    if (r) toast('تم تغيير العصابة', 'success');
    return !!r;
}

PAGES.jobs = {
    title: 'القطاعات',
    async render() {
        const res = await call('getJobs');
        if (!res) return null;
        return h('div', { class: 'grid two' }, arr(res.jobs).map((j) => h('div', { class: 'stat clickable', style: j.onduty > 0 ? '--tone: var(--green)' : '--tone: var(--border)', onclick: () => go('job', j.name) },
            h('div', { class: 'value', style: 'font-size:17px' }, j.label),
            h('div', { class: 'label', style: 'margin-top:6px' }, `🟢 متصل ${j.online} | 🟩 في الدوام ${j.onduty} | 👥 الإجمالي ${j.total} | رتب ${arr(j.grades).length}`))));
    },
};

PAGES.job = {
    title: (name) => `القطاع: ${name}`,
    async render(name) {
        const res = await call('getJobMembers', name);
        if (!res) return null;
        const job = res.job;
        job.grades = arr(job.grades);
        const members = arr(res.members);
        const perms = res.perms || {};
        $('page-title').textContent = `قطاع ${job.label}`;
        const online = members.filter((m) => m.online).length;
        const onduty = members.filter((m) => m.onduty).length;

        return h('div', null,
            h('div', { class: 'grid stats', style: 'margin-bottom:14px' },
                stat('الموظفين', members.length), stat('المتصلين', online, 'green'), stat('في الدوام', onduty, 'blue')),
            card(h('span', null, `👥 موظفين ${job.label}`), perms.jobs ? h('div', { class: 'actions', style: 'margin-bottom:12px' }, btn('➕ توظيف مواطن', async () => {
                const v = await modal({ title: `توظيف في ${job.label}`, okText: 'التالي', fields: [{ name: 'cid', label: 'الرقم الوطني', required: true, max: 50 }] });
                if (v && await changeJob(v.cid, v.cid, job.name)) render();
            }, 'primary')) : null,
            members.length ? h('div', { class: 'list' }, members.map((m) => item({
                icon: m.isboss ? '👔' : dot(m.online),
                title: `${m.online ? `[${m.serverId}] ` : ''}${m.name || m.citizenid}`,
                sub: `${m.gradeLevel} - ${m.gradeName}${m.isboss ? ' (مدير)' : ''} | ${m.online ? (m.onduty ? 'في الدوام' : 'متصل - خارج الدوام') : (m.status ? m.status.text : 'غير متصل')}`,
                side: [
                    btn('الملف', () => go('profile', m.citizenid), 'small'),
                    perms.jobs ? btn('الرتبة', async () => {
                        const level = await pickGrade(`رتبة ${m.name}`, arr(job.grades), m.gradeLevel);
                        if (level == null || level === m.gradeLevel) return;
                        if (await call('setCitizenJob', m.citizenid, job.name, level)) { toast('تم تغيير الرتبة', 'success'); render(); }
                    }, 'small blue') : null,
                    perms.jobs && m.online ? btn(m.onduty ? 'إنهاء الدوام' : 'تسجيل دوام', async () => {
                        if (await call('setCitizenDuty', m.citizenid, !m.onduty)) { toast('تم', 'success'); render(); }
                    }, 'small') : null,
                    perms.jobs && job.name !== S.config.unemployed ? btn('فصل', async () => { if (await fire(m.citizenid, m.name)) render(); }, 'small red') : null,
                ],
            }))) : empty('لا يوجد موظفين')),
        );
    },
};

// ═════ القضايا ═════
const STATUS = { new: ['جديدة', 'red'], review: ['قيد النظر', 'yellow'], closed: ['مغلقة', 'green'] };

PAGES.reports = {
    title: 'القضايا',
    async render(filter) {
        const res = await call('getJobReports', filter || null);
        if (!res) return null;
        const c = res.counts || {};
        S.info.newReports = c.new || 0;
        const chip = (f, label) => h('button', { class: 'chip' + ((filter || null) === f ? ' active' : ''), onclick: () => { S.current.arg = f; render(); } }, label);
        return h('div', null,
            h('div', { class: 'chips' }, chip(null, 'الكل'), chip('new', `🔴 جديدة (${c.new || 0})`), chip('review', `🟡 قيد النظر (${c.review || 0})`), chip('closed', `🟢 مغلقة (${c.closed || 0})`)),
            card(null, arr(res.reports).length ? h('div', { class: 'list' }, arr(res.reports).map((r) => item({
                icon: '⚖️',
                title: `#${r.id} | ${r.title}`,
                sub: `${r.caseType} | ${dot(r.submitterOnline)} ${r.name} | ${r.date}${r.defendantName ? ' | ضد: ' + r.defendantName : ''}${r.handledBy ? '\nالمعالج: ' + r.handledBy : ''}`,
                side: badge(STATUS[r.status] ? STATUS[r.status][0] : r.statusLabel, STATUS[r.status] ? STATUS[r.status][1] : ''),
                onclick: () => go('report', r.id),
            }))) : empty('لا توجد قضايا', '⚖️')),
        );
    },
};

PAGES.report = {
    title: (id) => `القضية #${id}`,
    async render(id) {
        const res = await call('getReport', id);
        if (!res) return null;
        const r = res.report;
        const perms = res.perms || {};
        const sub = r.submitter || {};
        const reload = () => render();

        return h('div', null,
            h('div', { class: 'profile-head' },
                h('div', { class: 'avatar' }, '⚖️'),
                h('div', { style: 'flex:1;min-width:0' },
                    h('div', { class: 'profile-name' }, r.title),
                    h('div', { class: 'profile-meta' }, badge(r.statusLabel, STATUS[r.status] ? STATUS[r.status][1] : ''), badge(r.caseType, 'blue'), badge(r.date, 'gray'),
                        r.handledBy ? badge(`المعالج: ${r.handledBy}`, 'gray') : null)),
            ),
            h('div', { class: 'actions', style: 'margin-bottom:14px' },
                btn('🔁 تغيير الحالة', async () => {
                    const v = await modal({ title: 'حالة القضية', fields: [{ name: 's', label: 'الحالة', type: 'select', value: r.status,
                        options: [{ value: 'new', label: 'جديدة' }, { value: 'review', label: 'قيد النظر' }, { value: 'closed', label: 'مغلقة' }] }] });
                    if (v && v.s !== r.status && await call('setReportStatus', r.id, v.s)) { toast('تم تحديث الحالة', 'success'); reload(); }
                }, 'blue'),
                btn('📝 إضافة ملاحظة', async () => {
                    const v = await modal({ title: 'ملاحظة على القضية', fields: [{ name: 'note', label: 'الملاحظة', type: 'textarea', required: true, max: S.config.noteMax || 500 }] });
                    if (v && await call('addReportNote', r.id, v.note)) { toast('تمت إضافة الملاحظة', 'success'); reload(); }
                }),
                sub.coords ? btn('📍 موقع التقديم', () => { nui('waypoint', { coords: sub.coords, label: `دعوى #${r.id}` }); toast('تم وضع علامة على الخريطة', 'success'); }) : null,
                perms.deleteReport ? btn('🗑️ حذف القضية', async () => {
                    if (await confirmBox('حذف القضية', `حذف القضية #${r.id} وكل ملاحظاتها نهائياً؟`, true) && await call('deleteReport', r.id)) { toast('تم حذف القضية', 'success'); back(); }
                }, 'red') : null,
            ),
            h('div', { class: 'grid two' },
                card('👤 مقدم الدعوى',
                    h('div', { class: 'item-sub', style: 'margin-bottom:10px' }, r.submitterStatus || ''),
                    kv([['الاسم', r.name], ['الرقم الوطني', r.citizenid], ['الجوال', r.phoneNumber], ['تاريخ الميلاد', sub.birthdate],
                        ['الجنس', gender(sub.gender)], ['الجنسية', sub.nationality], ['الوظيفة', `${val(sub.job)}${sub.jobGrade ? ' - ' + sub.jobGrade : ''}`],
                        ['العصابة', sub.gang], ['رقم الحساب', sub.account], ['موقع التقديم', sub.street]]),
                    perms.view ? h('div', { class: 'actions', style: 'margin-top:10px' }, btn('فتح الملف', () => go('profile', r.citizenid), 'small')) : null),
                card('🎯 المدعى عليه',
                    r.defendantStatus ? h('div', { class: 'item-sub', style: 'margin-bottom:10px' }, r.defendantStatus) : null,
                    kv([['الاسم', r.defendantName || 'غير محدد'], ['الرقم الوطني', r.defendantCitizenid || 'غير محدد']]),
                    perms.view && r.defendantCitizenid ? h('div', { class: 'actions', style: 'margin-top:10px' }, btn('فتح الملف', () => go('profile', r.defendantCitizenid), 'small')) : null),
            ),
            card('📄 تفاصيل الدعوى', h('div', { class: 'textblock' }, r.report)),
            r.witnesses ? card('👥 الشهود', h('div', { class: 'textblock' }, r.witnesses)) : null,
            r.evidence ? card('🔍 الأدلة', h('div', { class: 'textblock' }, r.evidence)) : null,
            card(`🗒️ ملاحظات الموظفين (${arr(r.notes).length})`, arr(r.notes).length ? h('div', { class: 'list' }, arr(r.notes).map((n) => h('div', { class: 'note' },
                h('div', { class: 'meta' }, `${n.author} - ${val(n.date)}`), n.note))) : empty('لا توجد ملاحظات', '🗒️')),
        );
    },
};

// ═════ المدينة ═════
PAGES.city = {
    title: 'نظام المدينة',
    async render() {
        const res = await call('getCityOverview');
        if (!res) return null;
        const o = res.overview;
        const perms = res.perms || {};

        const vInput = h('input', { placeholder: 'رقم اللوحة أو الرقم الوطني للمالك' });
        const vSearch = () => vInput.value.trim().length >= 2 && go('vehicles', vInput.value.trim());
        vInput.addEventListener('keydown', (e) => e.key === 'Enter' && vSearch());
        const pInput = h('input', { placeholder: 'اسم العقار أو الرقم الوطني للمالك' });
        const pSearch = () => pInput.value.trim().length >= 2 && go('properties', pInput.value.trim());
        pInput.addEventListener('keydown', (e) => e.key === 'Enter' && pSearch());

        const e = o.economy;
        return h('div', null,
            h('div', { class: 'grid stats', style: 'margin-bottom:14px' },
                stat('المتصلين', o.online, 'green'), stat('المواطنين', val(o.citizens)),
                arr(o.vehicles) ? stat('المركبات', arr(o.vehicles).total, 'blue') : null,
                arr(o.vehicles) ? stat('محجوزة', val(o.vehicles.impounded), 'red') : null,
                arr(o.houses) != null ? stat('العقارات', arr(o.houses), 'purple') : null,
                stat('استدعاءات مفتوحة', o.pendingSummons, 'yellow', perms.summon ? () => go('summons') : null),
            ),
            card('🏢 القطاعات في الدوام الآن', (o.duty || []).length ? h('div', { class: 'chips', style: 'margin:0' }, arr(o.duty).map((d) => badge(`${d.label}: ${d.count}`, 'green'))) : empty('لا أحد في الدوام')),
            h('div', { class: 'grid two' },
                arr(o.vehicles) ? card('🚗 سجل المركبات', h('div', { class: 'searchbar', style: 'margin:0' }, vInput, btn('بحث', vSearch, 'primary'))) : null,
                arr(o.houses) != null ? card('🏠 سجل العقارات', h('div', { class: 'searchbar', style: 'margin:0' }, pInput, btn('بحث', pSearch, 'primary'))) : null,
            ),
            e ? card(`💰 اقتصاد المدينة: ${money(e.total)}`,
                h('div', { class: 'grid stats', style: 'margin-bottom:12px' }, stat('البنوك', money(e.bank), 'green'), stat('الكاش', money(e.cash), 'gold')),
                h('div', { class: 'list' }, arr(e.richest).map((x, n) => item({
                    icon: n < 3 ? ['🥇', '🥈', '🥉'][n] : `${n + 1}`,
                    title: `${dot(x.status && x.status.online)} ${x.name}`,
                    sub: `المجموع ${money(x.bank + x.cash)} | البنك ${money(x.bank)} | الكاش ${money(x.cash)}`,
                    onclick: () => go('profile', x.citizenid),
                })))) : null,
            perms.announce ? card('📢 إعلان لكل المدينة', btn('كتابة إعلان', async () => {
                const v = await modal({ title: 'إعلان لكل المدينة', okText: 'إرسال', fields: [{ name: 'text', label: 'نص الإعلان', type: 'textarea', required: true, max: S.config.announceMax || 250 }] });
                if (v && await confirmBox('تأكيد الإعلان', `سيظهر لكل اللاعبين:\n\n${v.text}`) && await call('announce', v.text)) toast('تم إرسال الإعلان', 'success');
            }, 'primary')) : null,
        );
    },
};

PAGES.vehicles = {
    title: (q) => `المركبات: ${q}`,
    async render(q) {
        const res = await call('searchVehicles', q);
        if (!res) return null;
        return card(`نتائج (${arr(res.vehicles).length})`, arr(res.vehicles).length ? h('div', { class: 'list' }, arr(res.vehicles).map((v) => item({
            icon: v.stateCode === 2 ? '🔒' : '🚗',
            title: `${v.plate} | ${v.label}`,
            sub: `المالك: ${val(v.ownerName)} (${v.owner}) | ${v.state}${v.inWorld ? ' | 📍 في الشارع' : ''}`,
            onclick: () => go('vehicle', v.plate),
        }))) : empty('لا توجد مركبات', '🚗'));
    },
};

PAGES.vehicle = {
    title: (plate) => `المركبة ${plate}`,
    async render(plate) {
        const res = await call('getVehicle', plate);
        if (!res) return null;
        const v = res.vehicle;
        const perms = res.perms || {};
        const reload = () => render();
        const act = async (action, confirmText, extra) => {
            if (!await confirmBox('تأكيد', confirmText, action === 'impound')) return;
            const r = await call('vehicleAction', plate, action, extra);
            if (r) { toast(r.message, 'success'); reload(); }
        };
        return h('div', null,
            h('div', { class: 'profile-head' }, h('div', { class: 'avatar' }, v.stateCode === 2 ? '🔒' : '🚗'),
                h('div', null, h('div', { class: 'profile-name' }, `${v.label} | ${v.plate}`),
                    h('div', { class: 'profile-meta' }, badge(v.state, v.stateCode === 2 ? 'red' : 'green'), v.inWorld ? badge('📍 في الشارع الآن', 'blue') : null))),
            h('div', { class: 'actions', style: 'margin-bottom:14px' },
                perms.locate && v.inWorld ? btn('📍 تحديد الموقع', async () => {
                    const r = await call('getVehicle', plate, true);
                    if (r && r.vehicle.coords) toast(`المركبة في: ${val(r.vehicle.street)} - تم وضع علامة`, 'success', 7000);
                    else if (r) toast('المركبة لم تعد في الشارع', 'error');
                }, 'blue') : null,
                perms.vehicles ? (v.stateCode === 2 ? btn('🔓 فك الحجز', () => act('release', `فك حجز ${plate}؟`), 'green')
                    : btn('🔒 حجز', () => act('impound', `حجز ${plate} للمالك ${val(v.ownerName)}؟${v.inWorld ? '\nسيتم سحبها من الشارع' : ''}`), 'red')) : null,
                perms.vehicles ? btn('🔁 نقل الملكية', async () => {
                    const f = await modal({ title: `نقل ملكية ${plate}`, okText: 'التالي', fields: [{ name: 'cid', label: 'الرقم الوطني للمالك الجديد', required: true, max: 50 }] });
                    if (f) act('transfer', `نقل ملكية ${plate} إلى ${f.cid}؟`, f.cid);
                }, 'blue') : null,
                btn('👤 ملف المالك', () => go('profile', v.owner)),
            ),
            card(null, kv([['الموديل', v.model], ['المالك', `${val(v.ownerName)} (${v.owner})`], ['حالة المالك', v.ownerStatus], ['الكراج', v.garage], ['الحالة', v.state], ['رسوم الحجز', v.depotprice != null ? money(v.depotprice) : '-']])),
        );
    },
};

PAGES.properties = {
    title: (q) => `العقارات: ${q}`,
    async render(q) {
        const res = await call('searchProperties', q);
        if (!res) return null;
        const perms = res.perms || {};
        return card(`نتائج (${arr(res.properties).length})`, arr(res.properties).length ? h('div', { class: 'list' }, arr(res.properties).map((x) => item({
            icon: '🏠', title: x.label,
            sub: `المالك: ${val(x.ownerName)} (${val(x.owner)})\n${val(x.ownerStatus)}`,
            side: [
                x.owner ? btn('ملف المالك', () => go('profile', x.owner), 'small') : null,
                perms.properties ? btn('نقل الملكية', async () => {
                    const f = await modal({ title: `نقل ملكية ${x.label}`, fields: [{ name: 'cid', label: 'الرقم الوطني للمالك الجديد', required: true, max: 50 }] });
                    if (f && await confirmBox('تأكيد', `نقل ${x.label} إلى ${f.cid}؟`)) {
                        const r = await call('transferProperty', x.id, f.cid);
                        if (r) { toast(r.message, 'success'); render(); }
                    }
                }, 'small blue') : null,
            ],
        }))) : empty('لا توجد عقارات', '🏠'));
    },
};

PAGES.summons = {
    title: 'الاستدعاءات المفتوحة',
    async render() {
        const res = await call('getAllSummons');
        if (!res) return null;
        return card(`📜 المفتوحة (${arr(res.summons).length})`, arr(res.summons).length ? h('div', { class: 'list' }, arr(res.summons).map((s) => summonItem(s, () => render()))) : empty('لا توجد استدعاءات مفتوحة', '📜'));
    },
};

// ═════ سجل العمليات + التراجع والحذف ═════
async function logsView(citizenid, page, reload) {
    const res = await call('getLogs', citizenid || null, page || 0);
    if (!res) return null;
    const perms = res.perms || {};
    return card(`🗂️ ${res.total} عملية`,
        arr(res.logs).length ? h('div', { class: 'list' }, arr(res.logs).map((l) => item({
            icon: l.undoneBy ? '↩️' : '🗂️',
            title: `#${l.id} | ${l.action} | ${l.officer}`,
            sub: `${l.target ? 'المواطن: ' + l.target + '\n' : ''}${l.details ? l.details + '\n' : ''}${val(l.date)}${l.undoneBy ? `\n↩️ تم التراجع بواسطة ${l.undoneBy}` : ''}`,
            side: [
                l.targetCitizenid && !citizenid ? btn('الملف', () => go('profile', l.targetCitizenid), 'small') : null,
                perms.undo && l.undoable ? btn('↩️ تراجع', async () => {
                    if (!await confirmBox('التراجع عن الإجراء', `التراجع عن "${l.action}" #${l.id}؟\n${l.target ? 'المواطن: ' + l.target : ''}`)) return;
                    const r = await call('undoLog', l.id);
                    if (r) { toast(r.message, 'success'); reload(); }
                }, 'small green') : null,
                perms.delete ? btn('🗑️', async () => {
                    if (!await confirmBox('حذف السجل', `حذف السجل #${l.id} (${l.action})؟\nيبقى أثر إن فيه سجل انحذف.`, true)) return;
                    if (await call('deleteLog', l.id)) { toast('تم حذف السجل', 'success'); reload(); }
                }, 'small red') : null,
            ],
        }))) : empty('لا توجد عمليات', '🗂️'),
        pager(res.page, res.pages, (p) => { S.logsPage = p; reload(); }),
    );
}

PAGES.logs = {
    title: 'سجل العمليات',
    async render() {
        return logsView(null, S.logsPage || 0, () => render());
    },
};

// ═════ الفتح والإغلاق ═════
function renderMe() {
    $('me').replaceChildren(h('b', null, S.me.name || '-'), h('br'), h('span', null, `${val(S.me.job)} - ${val(S.me.grade)}`));
}

function openTablet(data) {
    S.open = true;
    S.info = data.info || {};
    S.perms = (data.info && data.info.perms) || {};
    S.me = data.me || {};
    S.config = data.config || {};
    S.stack = [];
    S.logsPage = 0;
    S.profileTab = null;
    renderMe();
    $('app').classList.remove('hidden');
    const start = data.page && PAGES[data.page] ? data.page : 'home';
    S.current = null;
    go(start, data.arg, true);
}

function closeTablet() {
    if (!S.open) return;
    S.open = false;
    closeModal();
    $('app').classList.add('hidden');
    nui('close');
}

window.addEventListener('message', (e) => {
    const d = e.data || {};
    if (d.action === 'open') openTablet(d);
    else if (d.action === 'close') { S.open = false; closeModal(); $('app').classList.add('hidden'); }
    else if (d.action === 'toast') toast(d.text, d.type);
});

document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || !S.open) return;
    if ($('modal-root').children.length) closeModal();
    else closeTablet();
});

$('btn-close').addEventListener('click', closeTablet);
$('btn-back').addEventListener('click', back);
$('btn-refresh').addEventListener('click', refresh);
