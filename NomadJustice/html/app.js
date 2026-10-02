'use strict';
/* ════════════════════════════════════════════════════════════════════════════
   NomadJustice - State Records interface
   All text is added as textContent (never HTML), so data cannot inject code
   ════════════════════════════════════════════════════════════════════════════ */

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'NomadJustice';
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

// ═════ DOM helpers ═════
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

// Lists from Lua: an empty list may arrive as {} instead of [] - this always returns an array
const arr = (x) => (Array.isArray(x) ? x : x && typeof x === 'object' ? Object.values(x) : []);
const val = (v) => (v === null || v === undefined || v === '' ? '-' : String(v));
const money = (n) => {
    const x = Math.floor(Number(n) || 0);
    return (x < 0 ? '-$' : '$') + Math.abs(x).toLocaleString('en-US');
};
const gender = (g) => (Number(g) === 0 ? 'Male' : Number(g) === 1 ? 'Female' : '-');
const dot = (online) => (online ? '🟢' : '⚫');

// ═════ Lua bridge ═════
async function nui(endpoint, data) {
    try {
        const res = await fetch(`https://${RES}/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        });
        return await res.json();
    } catch (e) {
        return { ok: false, err: 'Connection failed' };
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
        toast((res && res.err) || 'Something went wrong', 'error');
        return null;
    }
    if (res.perms) S.perms = res.perms;
    return res;
}

// ═════ Toasts ═════
function toast(text, type = 'info', ms = 4000) {
    const el = h('div', { class: `toast ${type}` }, text);
    $('toasts').append(el);
    setTimeout(() => el.remove(), ms);
}

// ═════ Input and confirm dialogs ═════
function closeModal() {
    const finish = S.modalFinish;
    S.modalFinish = null;
    $('modal-root').replaceChildren();
    if (finish) finish(null);
}

function modal({ title, text, fields = [], okText = 'Confirm', danger = false }) {
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
                if (field.required && v === '') { input.focus(); toast(`${field.label} is required`, 'error'); return; }
                if (field.type === 'number') {
                    v = v === '' ? null : Number(v);
                    if (v !== null && (!Number.isFinite(v) || (field.min != null && v < field.min))) { input.focus(); toast(`${field.label} is invalid`, 'error'); return; }
                    if (v !== null && field.maxValue != null && v > field.maxValue) { input.focus(); toast(`${field.label}: maximum is ${field.maxValue.toLocaleString('en-US')}`, 'error'); return; }
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
                    h('button', { class: 'btn', onclick: () => finish(null) }, 'Cancel'),
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

const confirmBox = (title, text, danger) => modal({ title, text, danger, okText: danger ? 'Yes, I am sure' : 'Confirm' });

// ═════ Building blocks ═════
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
        title: `${c.serverId ? `[${c.serverId}] ` : ''}${c.name || 'Unnamed'}`,
        sub: `${c.status ? c.status.text : ''}\nCitizen ID: ${c.citizenid} | ${val(c.job)} | Phone: ${val(c.phone)}`,
        side: c.suspended ? badge('Services suspended', 'red') : null,
        onclick: () => go('profile', c.citizenid),
    });
}

function pager(page, pages, onPage) {
    if (pages <= 1) return null;
    return h('div', { class: 'pager' },
        h('button', { class: 'btn small', disabled: page <= 0 || null, onclick: () => onPage(page - 1) }, '← Previous'),
        `Page ${page + 1} of ${pages}`,
        h('button', { class: 'btn small', disabled: page + 1 >= pages || null, onclick: () => onPage(page + 1) }, 'Next →'),
    );
}

// ═════ Navigation ═════
const NAV_BY_ROLE = {};
NAV_BY_ROLE.justice = [
    { page: 'home', icon: '🏠', label: 'Dashboard' },
    { page: 'online', icon: '🟢', label: 'Online Citizens' },
    { page: 'citizens', icon: '👥', label: 'Citizen Registry' },
    { page: 'search', icon: '🔎', label: 'Records Search' },
    { page: 'reports', icon: '⚖️', label: 'Case Files', perm: 'reports', badge: () => S.info.newReports },
    { page: 'jobs', icon: '🏢', label: 'Departments' },
    { page: 'city', icon: '🏙️', label: 'City Affairs', perm: 'city' },
    { page: 'summons', icon: '📜', label: 'Court Summonses', perm: 'summon' },
    { page: 'suspended', icon: '⛔', label: 'Suspended Services', badge: () => S.info.suspended },
    { page: 'suspects', icon: '🕵️', label: 'Persons of Interest', badge: () => S.info.suspects },
    { page: 'warrants', icon: '🚨', label: 'Warrants' },
    { page: 'policeRequests', icon: '🚓', label: 'Police Requests', perm: 'policeRequests', badge: () => S.info.policeRequests },
    { page: 'stats', icon: '📊', label: 'Statistics', perm: 'stats' },
    { page: 'finance', icon: '💰', label: 'Department Finance', show: () => !!S.info.finance },
    { page: 'logs', icon: '🗂️', label: 'Audit Log', perm: 'logs' },
];
NAV_BY_ROLE.police = [
    { page: 'phome', icon: '🏠', label: 'Dashboard' },
    { page: 'psearch', icon: '🔎', label: 'Citizen Lookup', perm: 'search' },
    { page: 'pwarrants', icon: '🚨', label: 'Active Warrants', perm: 'warrants', badge: () => S.info.warrants },
    { page: 'psuspects', icon: '🕵️', label: 'Persons of Interest', perm: 'suspects' },
    { page: 'prequests', icon: '📨', label: 'My DOJ Requests', perm: 'requests', badge: () => S.info.myPending },
    { page: 'finance', icon: '💰', label: 'Finance Office', show: () => !!S.info.finance },
];
NAV_BY_ROLE.sector = [
    { page: 'finance', icon: '💰', label: 'Finance Office' },
];
NAV_BY_ROLE.lawyer = [
    { page: 'lcases', icon: '💼', label: 'My Cases' },
];
const currentNav = () => NAV_BY_ROLE[S.role] || [];
const homePage = () => ({ justice: 'home', police: 'phome', lawyer: 'lcases', sector: 'finance' })[S.role] || 'home';

function renderNav() {
    const NAV = currentNav();
    const root = S.stack.length ? S.stack[0].page : homePage();
    const active = S.current ? S.current.page : homePage();
    $('nav').replaceChildren(...NAV.filter((n) => (!n.perm || S.perms[n.perm]) && (!n.show || n.show())).map((n) => {
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
        node = empty('Could not render this page', '⚠️');
    }
    if (S.renderToken !== token) return; // another page was opened while loading
    content.replaceChildren(node || empty('Could not load data', '⚠️'));
    content.scrollTop = 0;
    renderNav();
}

const refresh = () => render();

// ═════ Pages ═════
const PAGES = {};

PAGES.home = {
    title: 'Dashboard',
    async render() {
        const info = await call('panelInfo');
        if (!info) return null;
        S.info = info;
        const quick = h('input', { placeholder: 'Quick search: name / citizen ID / phone / server ID' });
        quick.addEventListener('keydown', (e) => { if (e.key === 'Enter' && quick.value.trim()) go('search', quick.value.trim()); });

        return h('div', null,
            h('div', { class: 'grid stats' },
                stat('Online Now', info.online, 'green', () => go('online')),
                stat('Registered Citizens', info.totalCitizens, 'gold', () => go('citizens')),
                stat('DOJ On Duty', info.justiceOnDuty, 'blue', () => go('jobs')),
                S.perms.reports ? stat('New Cases', info.newReports, 'yellow', () => go('reports')) : null,
                stat('Suspended Services', info.suspended, 'red', () => go('suspended')),
                stat('Active Warrants', info.warrants, 'red', () => go('warrants')),
                stat('Persons of Interest', info.suspects, 'purple', () => go('suspects')),
                S.perms.policeRequests ? stat('Police Requests', info.policeRequests, 'blue', () => go('policeRequests')) : null,
            ),
            h('div', { style: 'height:14px' }),
            card('🔎 Quick Search', h('div', { class: 'searchbar' }, quick, btn('Search', () => quick.value.trim() && go('search', quick.value.trim()), 'primary'))),
            card('⚡ Shortcuts', h('div', { class: 'actions' },
                btn('🟢 Online Citizens', () => go('online')),
                btn('👥 Citizen Registry', () => go('citizens')),
                S.perms.reports ? btn('⚖️ Case Files', () => go('reports')) : null,
                btn('🏢 Departments', () => go('jobs')),
                S.perms.city ? btn('🏙️ City Affairs', () => go('city')) : null,
                S.perms.logs ? btn('🗂️ Audit Log', () => go('logs')) : null,
            )),
        );
    },
};

PAGES.online = {
    title: 'Online Citizens',
    async render() {
        const res = await call('getOnlinePlayers');
        if (!res) return null;
        return card(`🟢 Online Now (${arr(res.players).length})`,
            arr(res.players).length ? h('div', { class: 'list' }, arr(res.players).map(citizenItem)) : empty('No players online'));
    },
};

PAGES.citizens = {
    title: 'Citizen Registry',
    async render(arg) {
        const state = arg || { page: 0, filter: 'all' };
        const res = await call('getAllCitizens', state.page, state.filter);
        if (!res) return null;
        const set = (patch) => { S.current.arg = { ...state, ...patch }; render(); };
        const chip = (f, label) => h('button', { class: 'chip' + (res.filter === f ? ' active' : ''), onclick: () => set({ filter: f, page: 0 }) }, label);
        return h('div', null,
            h('div', { class: 'chips' }, chip('all', `All`), chip('online', `🟢 Online (${res.online})`), chip('offline', '⚫ Offline')),
            card(`👥 ${res.total} citizens`,
                arr(res.list).length ? h('div', { class: 'list' }, arr(res.list).map(citizenItem)) : empty('No citizens found'),
                pager(res.page, res.pages, (p) => set({ page: p })),
            ),
        );
    },
};

PAGES.search = {
    title: 'Records Search',
    async render(query) {
        const input = h('input', { placeholder: 'Name / citizen ID / phone / server ID', value: query || '' });
        const doSearch = () => { const q = input.value.trim(); if (q) { S.current.arg = q; render(); } };
        input.addEventListener('keydown', (e) => { if (e.key === 'Enter') doSearch(); });
        setTimeout(() => input.focus(), 50);

        let results = null;
        if (query) {
            const res = await call('searchCitizens', query);
            results = res ? card(`Results (${arr(res.results).length})`, arr(res.results).length ? h('div', { class: 'list' }, arr(res.results).map(citizenItem)) : empty('No results', '🔍')) : null;
        }
        return h('div', null, h('div', { class: 'searchbar' }, input, btn('Search', doSearch, 'primary')), results || empty('Type in the search box (includes offline citizens)', '🔎'));
    },
};

PAGES.suspended = {
    title: 'Suspended Services',
    async render() {
        const res = await call('getSuspended');
        if (!res) return null;
        return card(`⛔ Suspended (${arr(res.list).length})`, arr(res.list).length ? h('div', { class: 'list' }, arr(res.list).map((s) => item({
            icon: '⛔',
            title: `${s.status && s.status.online ? '🟢 ' : ''}${s.name} (${s.citizenid})`,
            sub: `Reason: ${val(s.reason)}\nBy ${val(s.officer)} - ${val(s.date)}`,
            onclick: () => go('profile', s.citizenid),
        }))) : empty('No suspended citizens', '✅'));
    },
};

// ═════ Citizen record ═════
PAGES.profile = {
    title: (cid) => `Citizen Record ${cid}`,
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
                h('div', { class: 'profile-name' }, p.name || 'Unnamed'),
                h('div', { class: 'profile-meta' },
                    badge(p.status ? p.status.text : (p.online ? 'Online' : 'Offline'), p.online ? 'green' : 'gray'),
                    badge(`Citizen ID: ${p.citizenid}`),
                    badge(`${val(p.job.label)} - ${val(p.job.grade)}`, 'blue'),
                    p.gang ? badge(`🎭 ${p.gang.label}`, 'yellow') : null,
                    p.online ? badge(`Ping ${val(p.ping)}ms`, 'gray') : null,
                ),
            ),
        );

        const alert = h('div', null,
            p.suspension ? h('div', { class: 'alert red' }, `⛔ Services suspended: ${val(p.suspension.reason)} (by ${val(p.suspension.officer)} - ${val(p.suspension.date)})`) : null,
            courtAlerts(p.court));

        const actions = h('div', { class: 'actions', style: 'margin-bottom:14px' }, profileActions(p, perms, reload));

        const tabs = [
            ['personal', '🪪 Identity'], ['money', '💰 Finances'], ['job', '💼 Employment & Record'],
            ['licenses', '📄 Licenses'], ['vehicles', `🚗 Vehicles${p.vehicles ? ` (${arr(p.vehicles).length})` : ''}`],
            ['houses', `🏠 Properties${p.houses ? ` (${arr(p.houses).length})` : ''}`], ['items', `📦 Possessions (${arr(p.items).length})`],
            ['reports', `⚖️ Cases (${arr(p.reports).length})`], ['summons', `📜 Summonses (${arr(p.summons).length})`],
            ['court', `🔨 Verdicts & Warrants (${arr(p.court && p.court.verdicts).length})`],
            perms.logs ? ['logs', '🗂️ Audit Log'] : null,
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

    if (perms.locate) list.push(btn('📍 Locate', async () => {
        const r = await call('locateCitizen', p.citizenid);
        if (r) toast(`${r.name} is at: ${val(r.street)}${r.inVehicle ? ' (in a vehicle)' : ''} - marked on the map`, 'success', 7000);
    }, 'blue'));

    if (perms.summon) list.push(btn('📜 Summon', async () => {
        const v = await modal({ title: `Summon ${p.name} to Court`, okText: 'Send', fields: [
            { name: 'reason', label: 'Reason', required: true, max: S.config.summonMax || 200 },
            { name: 'appointment', label: 'Date & Time', placeholder: 'e.g. Thursday 9 PM', max: 100 },
            { name: 'location', label: 'Location', placeholder: 'e.g. Main Courtroom', max: 100 },
        ] });
        if (!v) return;
        const r = await call('sendSummon', p.citizenid, v.reason, v.appointment || '', v.location || '');
        if (r) { toast(r.delivered ? 'Summons delivered' : 'Saved, it will be delivered when they connect', 'success'); reload(); }
    }));

    if (!self && perms.withdraw) list.push(btn('💸 Bank Seizure', async () => {
        const maxValue = Math.min(S.config.withdrawMax || 5000000, Math.max(0, p.money.bank));
        const v = await modal({ title: `Seize from ${p.name}'s account`, text: `Current balance: ${money(p.money.bank)}`, okText: 'Continue', fields: [
            { name: 'amount', label: 'Amount', type: 'number', required: true, min: 1, maxValue },
            { name: 'reason', label: 'Reason', required: true, max: 200 },
        ] });
        if (!v || !await confirmBox('Confirm Seizure', `Seize ${money(v.amount)} from ${p.name}\nReason: ${v.reason}`, true)) return;
        const r = await call('withdrawBank', p.citizenid, v.amount, v.reason);
        if (r) { toast(`Seized. New balance: ${money(r.newBalance)}`, 'success'); reload(); }
    }, 'red'));

    if (!self && perms.compensation && p.online) list.push(btn('🤝 Compensation', async () => {
        const v = await modal({ title: `Compensate ${p.name}`, text: `They must be near you (${S.config.compensationDistance || 5} m)`, fields: [
            { name: 'amount', label: 'Amount', type: 'number', required: true, min: 1, maxValue: S.config.compensationMax },
        ] });
        if (!v) return;
        await nui('compensate', { citizenid: p.citizenid, amount: v.amount });
        setTimeout(reload, 800);
    }, 'green'));

    if (!self && perms.suspend) {
        if (p.suspension) list.push(btn('🔓 Lift Suspension', async () => {
            if (!await confirmBox('Lift Service Suspension', `Lift the service suspension for ${p.name}?`)) return;
            if (await call('unsuspendCitizen', p.citizenid)) { toast('Suspension lifted', 'success'); reload(); }
        }, 'green'));
        else list.push(btn('⛔ Suspend Services', async () => {
            const v = await modal({ title: `Suspend services for ${p.name}`, okText: 'Suspend', danger: true, fields: [{ name: 'reason', label: 'Reason', required: true, max: 200 }] });
            if (v && await call('suspendCitizen', p.citizenid, v.reason)) { toast('Services suspended', 'success'); reload(); }
        }, 'red'));
    }

    if (!self && perms.jobs) list.push(btn('💼 Job & Grade', async () => { if (await changeJob(p.citizenid, p.name)) reload(); }, 'blue'));
    if (!self && perms.jobs && p.job.name !== S.config.unemployed) list.push(btn('❌ Terminate', async () => { if (await fire(p.citizenid, p.name)) reload(); }, 'red'));
    if (!self && perms.gangs) list.push(btn('🎭 Gang', async () => { if (await changeGang(p.citizenid, p.name)) reload(); }));

    if (!self && perms.verdicts) list.push(btn('🔨 Issue Verdict', async () => { if (await verdictFlow({ citizenid: p.citizenid, name: p.name })) reload(); }, 'red'));
    if (!self && perms.warrants) list.push(btn('🚨 Arrest / Search Warrant', async () => { if (await warrantFlow(p.citizenid, p.name)) reload(); }, 'red'));
    if (!self && perms.suspects) {
        const suspect = p.court && p.court.suspect;
        list.push(suspect
            ? btn('🕵️ Remove from Persons of Interest', async () => {
                if (await confirmBox('Remove Person of Interest', `Remove ${p.name} from the persons of interest list?`) && await call('removeSuspect', suspect.id)) { toast('Removed', 'success'); reload(); }
            })
            : btn('🕵️ Flag as Person of Interest', async () => { if (await suspectFlow(p.citizenid, p.name)) reload(); }, 'yellow'));
    }

    if (!self && perms.edit) list.push(btn('✏️ Edit Identity', async () => {
        const v = await modal({ title: `Edit identity of ${p.name}`, okText: 'Save', fields: [
            { name: 'firstname', label: 'First Name', required: true, value: p.firstname, max: 20 },
            { name: 'lastname', label: 'Last Name', required: true, value: p.lastname, max: 20 },
            { name: 'birthdate', label: 'Date of Birth', required: true, value: p.birthdate, max: 10, placeholder: 'YYYY-MM-DD' },
            { name: 'gender', label: 'Sex', type: 'select', value: p.gender === 1 ? '1' : '0', options: [{ value: '0', label: 'Male' }, { value: '1', label: 'Female' }] },
            { name: 'nationality', label: 'Nationality', required: true, value: p.nationality, max: 30 },
        ] });
        if (!v) return;
        v.gender = Number(v.gender);
        if (await call('editCitizen', p.citizenid, v)) { toast('Identity updated', 'success'); reload(); }
    }));

    return list;
}

async function profileTab(tab, p, perms, reload) {
    const i = p.info || {};
    switch (tab) {
        case 'personal':
            return card(null, kv([
                ['Full Name', p.name], ['Citizen ID', p.citizenid], ['Date of Birth', p.birthdate], ['Sex', gender(p.gender)],
                ['Nationality', p.nationality], ['Phone Number', p.phone], ['Bank Account', p.account], ['Blood Type', i.bloodtype],
                ['Fingerprint', i.fingerprint], ['Wallet ID', i.walletid], ['Last Saved', p.lastUpdated],
            ]));
        case 'money':
            return h('div', null,
                h('div', { class: 'grid stats', style: 'margin-bottom:14px' },
                    stat('Bank Balance', money(p.money.bank), 'green'), stat('Cash', money(p.money.cash), 'gold'),
                    p.money.crypto != null ? stat('Crypto', val(p.money.crypto), 'purple') : null),
                card('DOJ Transactions', (p.transactions || []).length ? h('div', { class: 'list' }, arr(p.transactions).map((t) => item({
                    icon: t.type === 'withdraw' ? '🔻' : '🔺',
                    title: `${t.type === 'withdraw' ? 'Seizure' : 'Compensation'} ${money(t.amount)}`,
                    sub: `${val(t.reason)}\nBy ${val(t.officer)} - ${val(t.date)}`,
                }))) : empty('No transactions')));
        case 'job':
            return card(null, kv([
                ['Job', `${val(p.job.label)} - ${val(p.job.grade)}`], ['Duty', p.job.onduty ? 'On duty' : 'Off duty'],
                ['Manager', p.job.isboss ? 'Yes' : 'No'], ['Gang', p.gang ? `${p.gang.label} - ${val(p.gang.grade)}` : 'None'],
                ['Jail', i.injail > 0 ? `Incarcerated (${i.injail} months)` : 'Not incarcerated'],
                ['Criminal Record', i.criminalRecord ? `On file${i.criminalRecordDate ? ' - ' + i.criminalRecordDate : ''}` : 'Clean'],
                ['Medical Status', i.isdead ? 'Deceased / Injured' : 'Healthy'], ['Callsign', i.callsign],
            ]));
        case 'licenses': {
            const canToggle = perms.licenses && !p.isSelf;
            return card(null, (p.licenses || []).length ? h('div', { class: 'list' }, arr(p.licenses).map((l) => item({
                icon: l.active ? '✅' : '❌',
                title: l.label,
                sub: l.active ? 'Valid' : 'Not held',
                side: canToggle ? btn(l.active ? 'Revoke' : 'Grant', async () => {
                    if (!await confirmBox(`${l.active ? 'Revoke' : 'Grant'} License`, `${l.active ? 'Revoke' : 'Grant'} ${l.label} for ${p.name}?`, l.active)) return;
                    if (await call('setLicense', p.citizenid, l.key, !l.active)) { toast('Done', 'success'); reload(); }
                }, `small ${l.active ? 'red' : 'green'}`) : null,
            }))) : empty('No licenses'));
        }
        case 'vehicles':
            if (!p.vehicles) return empty('Vehicle registry is not enabled');
            return card(null, arr(p.vehicles).length ? h('div', { class: 'list' }, arr(p.vehicles).map((v) => item({
                icon: '🚗', title: `${v.label} | ${val(v.plate)}`,
                sub: `${v.state} | Garage: ${val(v.garage)} | Fuel ${val(v.fuel)}% | Engine ${val(v.engine)}% | Body ${val(v.body)}%`,
                onclick: perms.city && v.plate ? () => go('vehicle', v.plate) : null,
            }))) : empty('No registered vehicles', '🚗'));
        case 'houses':
            if (!p.houses) return empty('Property registry is not enabled');
            return card(null, arr(p.houses).length ? h('div', { class: 'list' }, arr(p.houses).map((x) => item({ icon: '🏠', title: x.label }))) : empty('No properties', '🏠'));
        case 'items':
            return card(null, arr(p.items).length ? h('div', { class: 'list' }, arr(p.items).map((x) => item({ icon: '📦', title: x.label, side: badge(`× ${x.amount}`) }))) : empty('No possessions', '📦'));
        case 'reports':
            return card(null, arr(p.reports).length ? h('div', { class: 'list' }, arr(p.reports).map((r) => item({
                icon: '⚖️', title: `#${r.id} | ${r.title}`, sub: `${r.role} | ${val(r.caseType)} | ${val(r.status)} | ${val(r.date)}`,
                onclick: perms.reports ? () => go('report', r.id) : null,
            }))) : empty('No cases', '⚖️'));
        case 'summons':
            return card(null, arr(p.summons).length ? h('div', { class: 'list' }, arr(p.summons).map((s) => summonItem(s, reload))) : empty('No summonses', '📜'));
        case 'court':
            return courtView(p.court || {}, perms, reload, { citizenid: p.citizenid, name: p.name });
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
        sub: `${s.reason}\nWhen: ${val(s.appointment)} | Where: ${val(s.location)}\nBy ${val(s.officer)} - ${val(s.date)}`,
        side: [
            s.citizenid ? btn('Record', () => go('profile', s.citizenid), 'small') : null,
            open && S.perms.summon ? btn('Update', async () => {
                const v = await modal({ title: `Update Summons #${s.id}`, fields: [{ name: 'status', label: 'Status', type: 'select', options: [
                    { value: 'attended', label: 'Appeared' }, { value: 'absent', label: 'Failed to appear' }, { value: 'cancelled', label: 'Cancel summons' }] }] });
                if (v && await call('setSummonStatus', s.id, v.status)) { toast('Summons updated', 'success'); reload(); }
            }, 'small') : null,
            S.perms.delete ? btn('Delete', async () => {
                if (await confirmBox('Delete Summons', `Permanently delete summons #${s.id}?`, true) && await call('deleteSummon', s.id)) { toast('Deleted', 'success'); reload(); }
            }, 'small red') : null,
        ],
    });
}

// ═════ Jobs and gangs ═════
async function pickGrade(title, grades, current) {
    grades = arr(grades);
    if (!grades.length) { toast('No grades available', 'error'); return null; }
    const v = await modal({ title, fields: [{ name: 'level', label: 'Grade', type: 'select', value: current != null ? String(current) : String(grades[0].level),
        options: grades.map((g) => ({ value: g.level, label: `${g.level} - ${g.name}${g.isboss ? ' (manager)' : ''}` })) }] });
    return v ? Number(v.level) : null;
}

async function changeJob(cid, name, presetJob) {
    const res = await call('getJobs');
    if (!res) return false;
    let job = presetJob ? arr(res.jobs).find((j) => j.name === presetJob) : null;
    if (!job) {
        const v = await modal({ title: `Employment of ${name}`, okText: 'Next', fields: [{ name: 'job', label: 'Department', type: 'select',
            options: arr(res.jobs).map((j, i) => ({ value: i, label: `${j.label} (${j.name})` })) }] });
        if (!v) return false;
        job = arr(res.jobs)[Number(v.job)];
    }
    const level = await pickGrade(`Grade in ${job.label}`, arr(job.grades));
    if (level == null) return false;
    const grade = arr(job.grades).find((g) => g.level === level);
    if (!await confirmBox('Confirm', `Appoint ${name} to ${job.label} as ${grade ? grade.name : level}?`)) return false;
    const r = await call('setCitizenJob', cid, job.name, level);
    if (r) toast(`Appointed: ${r.newJob}`, 'success');
    return !!r;
}

async function fire(cid, name) {
    if (!await confirmBox('Terminate Employment', `Terminate ${name} from their job?`, true)) return false;
    const r = await call('setCitizenJob', cid, S.config.unemployed, 0);
    if (r) toast('Employment terminated', 'success');
    return !!r;
}

async function changeGang(cid, name) {
    const res = await call('getGangs');
    if (!res) return false;
    const v = await modal({ title: `Gang of ${name}`, okText: 'Next', fields: [{ name: 'gang', label: 'Gang', type: 'select',
        options: arr(res.gangs).map((g, i) => ({ value: i, label: `${g.label} (${g.name})` })) }] });
    if (!v) return false;
    const gang = arr(res.gangs)[Number(v.gang)];
    const level = await pickGrade(`Rank in ${gang.label}`, arr(gang.grades));
    if (level == null) return false;
    const r = await call('setGang', cid, gang.name, level);
    if (r) toast('Gang updated', 'success');
    return !!r;
}

PAGES.jobs = {
    title: 'Departments',
    async render() {
        const res = await call('getJobs');
        if (!res) return null;
        return h('div', { class: 'grid two' }, arr(res.jobs).map((j) => h('div', { class: 'stat clickable', style: j.onduty > 0 ? '--tone: var(--green)' : '--tone: var(--border)', onclick: () => go('job', j.name) },
            h('div', { class: 'value', style: 'font-size:17px' }, j.label),
            h('div', { class: 'label', style: 'margin-top:6px' }, `🟢 Online ${j.online} | 🟩 On duty ${j.onduty} | 👥 Total ${j.total} | Grades ${arr(j.grades).length}`))));
    },
};

PAGES.job = {
    title: (name) => `Department: ${name}`,
    async render(name) {
        const res = await call('getJobMembers', name);
        if (!res) return null;
        const job = res.job;
        job.grades = arr(job.grades);
        const members = arr(res.members);
        const perms = res.perms || {};
        $('page-title').textContent = `Department: ${job.label}`;
        const online = members.filter((m) => m.online).length;
        const onduty = members.filter((m) => m.onduty).length;

        return h('div', null,
            h('div', { class: 'grid stats', style: 'margin-bottom:14px' },
                stat('Employees', members.length), stat('Online', online, 'green'), stat('On Duty', onduty, 'blue')),
            card(h('span', null, `👥 ${job.label} Staff`), perms.jobs ? h('div', { class: 'actions', style: 'margin-bottom:12px' }, btn('➕ Hire Citizen', async () => {
                const v = await modal({ title: `Hire into ${job.label}`, okText: 'Next', fields: [{ name: 'cid', label: 'Citizen ID', required: true, max: 50 }] });
                if (v && await changeJob(v.cid, v.cid, job.name)) render();
            }, 'primary')) : null,
            members.length ? h('div', { class: 'list' }, members.map((m) => item({
                icon: m.isboss ? '👔' : dot(m.online),
                title: `${m.online ? `[${m.serverId}] ` : ''}${m.name || m.citizenid}`,
                sub: `${m.gradeLevel} - ${m.gradeName}${m.isboss ? ' (manager)' : ''} | ${m.online ? (m.onduty ? 'On duty' : 'Online - off duty') : (m.status ? m.status.text : 'Offline')}`,
                side: [
                    btn('Record', () => go('profile', m.citizenid), 'small'),
                    perms.jobs ? btn('Grade', async () => {
                        const level = await pickGrade(`Grade for ${m.name}`, arr(job.grades), m.gradeLevel);
                        if (level == null || level === m.gradeLevel) return;
                        if (await call('setCitizenJob', m.citizenid, job.name, level)) { toast('Grade updated', 'success'); render(); }
                    }, 'small blue') : null,
                    perms.jobs && m.online ? btn(m.onduty ? 'Clock Out' : 'Clock In', async () => {
                        if (await call('setCitizenDuty', m.citizenid, !m.onduty)) { toast('Done', 'success'); render(); }
                    }, 'small') : null,
                    perms.jobs && job.name !== S.config.unemployed ? btn('Terminate', async () => { if (await fire(m.citizenid, m.name)) render(); }, 'small red') : null,
                ],
            }))) : empty('No employees')),
        );
    },
};

// ═════ Case files ═════
const STATUS = { new: ['New', 'red'], review: ['Under Review', 'yellow'], closed: ['Closed', 'green'] };

PAGES.reports = {
    title: 'Case Files',
    async render(filter) {
        const res = await call('getJobReports', filter || null);
        if (!res) return null;
        const c = res.counts || {};
        S.info.newReports = c.new || 0;
        const chip = (f, label) => h('button', { class: 'chip' + ((filter || null) === f ? ' active' : ''), onclick: () => { S.current.arg = f; render(); } }, label);
        return h('div', null,
            h('div', { class: 'chips' }, chip(null, 'All'), chip('new', `🔴 New (${c.new || 0})`), chip('review', `🟡 Under Review (${c.review || 0})`), chip('closed', `🟢 Closed (${c.closed || 0})`)),
            card(null, arr(res.reports).length ? h('div', { class: 'list' }, arr(res.reports).map((r) => item({
                icon: '⚖️',
                title: `#${r.id} | ${r.title}`,
                sub: `${r.caseType} | ${dot(r.submitterOnline)} ${r.name} | ${r.date}${r.defendantName ? ' | v. ' + r.defendantName : ''}${r.handledBy ? '\nHandled by: ' + r.handledBy : ''}`,
                side: badge(STATUS[r.status] ? STATUS[r.status][0] : r.statusLabel, STATUS[r.status] ? STATUS[r.status][1] : ''),
                onclick: () => go('report', r.id),
            }))) : empty('No cases', '⚖️')),
        );
    },
};

PAGES.report = {
    title: (id) => `Case #${id}`,
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
                        r.handledBy ? badge(`Handled by: ${r.handledBy}`, 'gray') : null)),
            ),
            h('div', { class: 'actions', style: 'margin-bottom:14px' },
                btn('🔁 Change Status', async () => {
                    const v = await modal({ title: 'Case Status', fields: [{ name: 's', label: 'Status', type: 'select', value: r.status,
                        options: [{ value: 'new', label: 'New' }, { value: 'review', label: 'Under Review' }, { value: 'closed', label: 'Closed' }] }] });
                    if (v && v.s !== r.status && await call('setReportStatus', r.id, v.s)) { toast('Status updated', 'success'); reload(); }
                }, 'blue'),
                btn('📝 Add Note', async () => {
                    const v = await modal({ title: 'Case Note', fields: [{ name: 'note', label: 'Note', type: 'textarea', required: true, max: S.config.noteMax || 500 }] });
                    if (v && await call('addReportNote', r.id, v.note)) { toast('Note added', 'success'); reload(); }
                }),
                sub.coords ? btn('📍 Filing Location', () => { nui('waypoint', { coords: sub.coords, label: `Case #${r.id}` }); toast('Marked on the map', 'success'); }) : null,
                perms.verdicts ? btn('🔨 Issue Verdict', async () => {
                    if (await verdictFlow({ reportId: r.id, citizenid: r.defendantCitizenid, name: r.defendantName, plaintiff: r.citizenid })) reload();
                }, 'red') : null,
                perms.deleteReport ? btn('🗑️ Delete Case', async () => {
                    if (await confirmBox('Delete Case', `Permanently delete case #${r.id} and all its notes?`, true) && await call('deleteReport', r.id)) { toast('Case deleted', 'success'); back(); }
                }, 'red') : null,
            ),
            h('div', { class: 'grid two' },
                card('👤 Plaintiff',
                    h('div', { class: 'item-sub', style: 'margin-bottom:10px' }, r.submitterStatus || ''),
                    kv([['Name', r.name], ['Citizen ID', r.citizenid], ['Phone', r.phoneNumber], ['Date of Birth', sub.birthdate],
                        ['Sex', gender(sub.gender)], ['Nationality', sub.nationality], ['Job', `${val(sub.job)}${sub.jobGrade ? ' - ' + sub.jobGrade : ''}`],
                        ['Gang', sub.gang], ['Bank Account', sub.account], ['Filing Location', sub.street]]),
                    perms.view ? h('div', { class: 'actions', style: 'margin-top:10px' }, btn('Open Record', () => go('profile', r.citizenid), 'small')) : null),
                card('🎯 Defendant',
                    r.defendantStatus ? h('div', { class: 'item-sub', style: 'margin-bottom:10px' }, r.defendantStatus) : null,
                    kv([['Name', r.defendantName || 'Not specified'], ['Citizen ID', r.defendantCitizenid || 'Not specified']]),
                    perms.view && r.defendantCitizenid ? h('div', { class: 'actions', style: 'margin-top:10px' }, btn('Open Record', () => go('profile', r.defendantCitizenid), 'small')) : null),
            ),
            card('📄 Complaint', h('div', { class: 'textblock' }, r.report)),
            r.witnesses ? card('👥 Witnesses', h('div', { class: 'textblock' }, r.witnesses)) : null,
            r.evidence ? card('🔍 Evidence', h('div', { class: 'textblock' }, r.evidence)) : null,
            caseLawyersCard(r, perms, reload),
            caseDocumentsCard(r, reload, true),
            arr(r.verdicts).length ? card(`🔨 Verdicts in this case (${arr(r.verdicts).length})`, h('div', { class: 'list' }, arr(r.verdicts).map(verdictItem))) : null,
            card(`🗒️ Staff Notes (${arr(r.notes).length})`, arr(r.notes).length ? h('div', { class: 'list' }, arr(r.notes).map((n) => h('div', { class: 'note' },
                h('div', { class: 'meta' }, `${n.author} - ${val(n.date)}`), n.note))) : empty('No notes', '🗒️')),
        );
    },
};

// ═════ City affairs ═════
PAGES.city = {
    title: 'City Affairs',
    async render() {
        const res = await call('getCityOverview');
        if (!res) return null;
        const o = res.overview;
        const perms = res.perms || {};

        const vInput = h('input', { placeholder: 'Plate number or owner citizen ID' });
        const vSearch = () => vInput.value.trim().length >= 2 && go('vehicles', vInput.value.trim());
        vInput.addEventListener('keydown', (e) => e.key === 'Enter' && vSearch());
        const pInput = h('input', { placeholder: 'Property name or owner citizen ID' });
        const pSearch = () => pInput.value.trim().length >= 2 && go('properties', pInput.value.trim());
        pInput.addEventListener('keydown', (e) => e.key === 'Enter' && pSearch());

        const e = o.economy;
        return h('div', null,
            h('div', { class: 'grid stats', style: 'margin-bottom:14px' },
                stat('Online', o.online, 'green'), stat('Citizens', val(o.citizens)),
                arr(o.vehicles) ? stat('Vehicles', arr(o.vehicles).total, 'blue') : null,
                arr(o.vehicles) ? stat('Impounded', val(o.vehicles.impounded), 'red') : null,
                arr(o.houses) != null ? stat('Properties', arr(o.houses), 'purple') : null,
                stat('Open Summonses', o.pendingSummons, 'yellow', perms.summon ? () => go('summons') : null),
            ),
            card('🏢 Departments On Duty', (o.duty || []).length ? h('div', { class: 'chips', style: 'margin:0' }, arr(o.duty).map((d) => badge(`${d.label}: ${d.count}`, 'green'))) : empty('Nobody on duty')),
            h('div', { class: 'grid two' },
                arr(o.vehicles) ? card('🚗 Vehicle Registry', h('div', { class: 'searchbar', style: 'margin:0' }, vInput, btn('Search', vSearch, 'primary'))) : null,
                arr(o.houses) != null ? card('🏠 Property Registry', h('div', { class: 'searchbar', style: 'margin:0' }, pInput, btn('Search', pSearch, 'primary'))) : null,
            ),
            e && arr(e.sectors).length ? card('🏛️ Department Balances', h('div', { class: 'grid stats' }, arr(e.sectors).map((x) => stat(x.label, x.balance != null ? money(x.balance) : '-', 'blue')))) : null,
            e ? card(`💰 City Economy: ${money(e.total)}`,
                h('div', { class: 'grid stats', style: 'margin-bottom:12px' }, stat('Bank Deposits', money(e.bank), 'green'), stat('Cash', money(e.cash), 'gold')),
                h('div', { class: 'list' }, arr(e.richest).map((x, n) => item({
                    icon: n < 3 ? ['🥇', '🥈', '🥉'][n] : `${n + 1}`,
                    title: `${dot(x.status && x.status.online)} ${x.name}`,
                    sub: `Total ${money(x.bank + x.cash)} | Bank ${money(x.bank)} | Cash ${money(x.cash)}`,
                    onclick: () => go('profile', x.citizenid),
                })))) : null,
            perms.announce ? card('📢 City-wide Announcement', btn('Write Announcement', async () => {
                const v = await modal({ title: 'City-wide Announcement', okText: 'Send', fields: [{ name: 'text', label: 'Announcement', type: 'textarea', required: true, max: S.config.announceMax || 250 }] });
                if (v && await confirmBox('Confirm Announcement', `This will be shown to every player:\n\n${v.text}`) && await call('announce', v.text)) toast('Announcement sent', 'success');
            }, 'primary')) : null,
        );
    },
};

PAGES.vehicles = {
    title: (q) => `Vehicles: ${q}`,
    async render(q) {
        const res = await call('searchVehicles', q);
        if (!res) return null;
        return card(`Results (${arr(res.vehicles).length})`, arr(res.vehicles).length ? h('div', { class: 'list' }, arr(res.vehicles).map((v) => item({
            icon: v.stateCode === 2 ? '🔒' : '🚗',
            title: `${v.plate} | ${v.label}`,
            sub: `Owner: ${val(v.ownerName)} (${v.owner}) | ${v.state}${v.inWorld ? ' | 📍 On the street' : ''}`,
            onclick: () => go('vehicle', v.plate),
        }))) : empty('No vehicles found', '🚗'));
    },
};

PAGES.vehicle = {
    title: (plate) => `Vehicle ${plate}`,
    async render(plate) {
        const res = await call('getVehicle', plate);
        if (!res) return null;
        const v = res.vehicle;
        const perms = res.perms || {};
        const reload = () => render();
        const act = async (action, confirmText, extra) => {
            if (!await confirmBox('Confirm', confirmText, action === 'impound')) return;
            const r = await call('vehicleAction', plate, action, extra);
            if (r) { toast(r.message, 'success'); reload(); }
        };
        return h('div', null,
            h('div', { class: 'profile-head' }, h('div', { class: 'avatar' }, v.stateCode === 2 ? '🔒' : '🚗'),
                h('div', null, h('div', { class: 'profile-name' }, `${v.label} | ${v.plate}`),
                    h('div', { class: 'profile-meta' }, badge(v.state, v.stateCode === 2 ? 'red' : 'green'), v.inWorld ? badge('📍 On the street now', 'blue') : null))),
            h('div', { class: 'actions', style: 'margin-bottom:14px' },
                perms.locate && v.inWorld ? btn('📍 Locate', async () => {
                    const r = await call('getVehicle', plate, true);
                    if (r && r.vehicle.coords) toast(`Vehicle is at: ${val(r.vehicle.street)} - marked`, 'success', 7000);
                    else if (r) toast('The vehicle is no longer on the street', 'error');
                }, 'blue') : null,
                perms.vehicles ? (v.stateCode === 2 ? btn('🔓 Release', () => act('release', `Release ${plate} from impound?`), 'green')
                    : btn('🔒 Impound', () => act('impound', `Impound ${plate} owned by ${val(v.ownerName)}?${v.inWorld ? '\nIt will be removed from the street' : ''}`), 'red')) : null,
                perms.vehicles ? btn('🔁 Transfer Title', async () => {
                    const f = await modal({ title: `Transfer title of ${plate}`, okText: 'Next', fields: [{ name: 'cid', label: 'New owner citizen ID', required: true, max: 50 }] });
                    if (f) act('transfer', `Transfer ${plate} to ${f.cid}?`, f.cid);
                }, 'blue') : null,
                btn('👤 Owner Record', () => go('profile', v.owner)),
            ),
            card(null, kv([['Model', v.model], ['Owner', `${val(v.ownerName)} (${v.owner})`], ['Owner Status', v.ownerStatus], ['Garage', v.garage], ['State', v.state], ['Impound Fee', v.depotprice != null ? money(v.depotprice) : '-']])),
        );
    },
};

PAGES.properties = {
    title: (q) => `Properties: ${q}`,
    async render(q) {
        const res = await call('searchProperties', q);
        if (!res) return null;
        const perms = res.perms || {};
        return card(`Results (${arr(res.properties).length})`, arr(res.properties).length ? h('div', { class: 'list' }, arr(res.properties).map((x) => item({
            icon: '🏠', title: x.label,
            sub: `Owner: ${val(x.ownerName)} (${val(x.owner)})\n${val(x.ownerStatus)}`,
            side: [
                x.owner ? btn('Owner Record', () => go('profile', x.owner), 'small') : null,
                perms.properties ? btn('Transfer Deed', async () => {
                    const f = await modal({ title: `Transfer deed of ${x.label}`, fields: [{ name: 'cid', label: 'New owner citizen ID', required: true, max: 50 }] });
                    if (f && await confirmBox('Confirm', `Transfer ${x.label} to ${f.cid}?`)) {
                        const r = await call('transferProperty', x.id, f.cid);
                        if (r) { toast(r.message, 'success'); render(); }
                    }
                }, 'small blue') : null,
            ],
        }))) : empty('No properties found', '🏠'));
    },
};

PAGES.summons = {
    title: 'Open Summonses',
    async render() {
        const res = await call('getAllSummons');
        if (!res) return null;
        return card(`📜 Open (${arr(res.summons).length})`, arr(res.summons).length ? h('div', { class: 'list' }, arr(res.summons).map((s) => summonItem(s, () => render()))) : empty('No open summonses', '📜'));
    },
};

// ═════ Audit log + undo and delete ═════
async function logsView(citizenid, page, reload) {
    const res = await call('getLogs', citizenid || null, page || 0);
    if (!res) return null;
    const perms = res.perms || {};
    return card(`🗂️ ${res.total} actions`,
        arr(res.logs).length ? h('div', { class: 'list' }, arr(res.logs).map((l) => item({
            icon: l.undoneBy ? '↩️' : '🗂️',
            title: `#${l.id} | ${l.action} | ${l.officer}`,
            sub: `${l.target ? 'Citizen: ' + l.target + '\n' : ''}${l.details ? l.details + '\n' : ''}${val(l.date)}${l.undoneBy ? `\n↩️ Undone by ${l.undoneBy}` : ''}`,
            side: [
                l.targetCitizenid && !citizenid ? btn('Record', () => go('profile', l.targetCitizenid), 'small') : null,
                perms.undo && l.undoable ? btn('↩️ Undo', async () => {
                    if (!await confirmBox('Undo Action', `Undo "${l.action}" #${l.id}?\n${l.target ? 'Citizen: ' + l.target : ''}`)) return;
                    const r = await call('undoLog', l.id);
                    if (r) { toast(r.message, 'success'); reload(); }
                }, 'small green') : null,
                perms.delete ? btn('🗑️', async () => {
                    if (!await confirmBox('Delete Entry', `Delete entry #${l.id} (${l.action})?\nA trace that an entry was deleted is kept.`, true)) return;
                    if (await call('deleteLog', l.id)) { toast('Entry deleted', 'success'); reload(); }
                }, 'small red') : null,
            ],
        }))) : empty('No actions', '🗂️'),
        pager(res.page, res.pages, (p) => { S.logsPage = p; reload(); }),
    );
}

PAGES.logs = {
    title: 'Audit Log',
    async render() {
        return logsView(null, S.logsPage || 0, () => render());
    },
};

// ════════════════════════════════════════════════════════════════════════════
// Court: verdicts, warrants, persons of interest, attorneys and documents
// ════════════════════════════════════════════════════════════════════════════
const DANGER = { high: ['High risk', 'red'], medium: ['Medium risk', 'yellow'], low: ['Low risk', 'gray'] };
const WSTATUS = { active: 'red', executed: 'green', cancelled: 'gray', expired: 'gray' };

function courtAlerts(court) {
    if (!court) return null;
    const active = arr(court.warrants).filter((w) => w.status === 'active');
    return h('div', null,
        court.suspect ? h('div', { class: 'alert yellow' }, `🕵️ Person of interest (${(DANGER[court.suspect.danger] || [court.suspect.dangerLabel])[0]}): ${court.suspect.reason}`) : null,
        active.map((w) => h('div', { class: 'alert red' }, `🚨 Active ${w.typeLabel} #${w.id}: ${w.reason}${w.place ? ' | Location: ' + w.place : ''} (expires ${val(w.expires)})`)),
    );
}

function verdictItem(v) {
    const details = [
        v.amount > 0 ? money(v.amount) : null,
        v.target ? `to the injured party ${v.target}` : null,
        v.plate ? `vehicle ${v.plate}` : null,
        v.months > 0 ? `${v.months} months` : null,
        v.reportId ? `case #${v.reportId}` : null,
    ].filter(Boolean).join(' | ');
    return item({
        icon: v.status === 'cancelled' ? '↩️' : '🔨',
        title: `#${v.id} | ${v.typeLabel}${details ? ' | ' + details : ''}`,
        sub: `${v.text}\nJudge: ${v.judge} - ${val(v.date)}`,
        side: badge(v.statusLabel, v.status === 'cancelled' ? 'gray' : 'red'),
    });
}

function warrantItem(w, opts = {}) {
    return item({
        icon: w.type === 'search' ? '🔍' : '🚨',
        title: `#${w.id} | ${w.typeLabel} | ${w.name} (${w.citizenid})`,
        sub: `${w.reason}${w.place ? '\nLocation: ' + w.place : ''}\nIssued by: ${w.issuedBy}${w.requestedBy ? ' | Requested by: ' + w.requestedBy : ''} - ${val(w.date)}${w.status === 'active' ? '\nExpires: ' + val(w.expires) : ''}${w.executedBy ? '\nExecuted by: ' + w.executedBy : ''}${w.citizenStatus ? '\n' + w.citizenStatus.text : ''}`,
        side: [
            badge(w.statusLabel, WSTATUS[w.status]),
            opts.profile ? btn('Record', () => go(opts.profile, w.citizenid), 'small') : null,
            opts.cancel && w.status === 'active' ? btn('Cancel', async () => {
                if (await confirmBox('Cancel Warrant', `Cancel ${w.typeLabel} #${w.id}?`, true) && await call('cancelWarrant', w.id)) { toast('Warrant cancelled', 'success'); opts.reload(); }
            }, 'small red') : null,
            opts.execute && w.status === 'active' ? btn('✅ Mark Executed', async () => {
                if (await confirmBox('Execute Warrant', `Confirm execution of ${w.typeLabel} #${w.id} on ${w.name}?`) && await call('executeWarrant', w.id)) { toast('Execution recorded', 'success'); opts.reload(); }
            }, 'small green') : null,
        ],
    });
}

function suspectItem(s, profilePage, onRemove) {
    const d = DANGER[s.danger] || [s.dangerLabel, 'yellow'];
    return item({
        icon: '🕵️',
        title: `${s.status && s.status.online ? '🟢 ' : '⚫ '}${s.name} (${s.citizenid})`,
        sub: `${s.reason}\nAdded by: ${s.addedBy} - ${val(s.date)}`,
        side: [badge(d[0], d[1]), btn('Record', () => go(profilePage, s.citizenid), 'small'), onRemove ? btn('Remove', () => onRemove(s), 'small red') : null],
        onclick: () => go(profilePage, s.citizenid),
    });
}

function courtView(court, perms, reload, who) {
    return h('div', null,
        court.suspect ? card('🕵️ Persons of Interest', suspectItem(court.suspect, 'profile')) : null,
        card(`🚨 Arrest & Search Warrants (${arr(court.warrants).length})`, arr(court.warrants).length
            ? h('div', { class: 'list' }, arr(court.warrants).map((w) => warrantItem(w, { cancel: perms.warrants, execute: !!S.info.judge, reload })))
            : empty('No warrants', '🚨')),
        card(`🔨 Verdict Archive (${arr(court.verdicts).length})`, arr(court.verdicts).length
            ? h('div', { class: 'list' }, arr(court.verdicts).map(verdictItem))
            : empty('No verdicts', '🔨'),
            h('div', { class: 'item-sub', style: 'margin-top:8px' }, 'To reverse a verdict: Audit Log → "Issue Verdict" → ↩️ Undo (money and vehicle are returned automatically)')),
    );
}

const VERDICT_TYPES = [
    { value: 'fine', label: '💸 Fine (taken from their bank)' },
    { value: 'compensation', label: '🤝 Restitution (from their bank to the injured party)' },
    { value: 'impound', label: '🔒 Vehicle Impound' },
    { value: 'jail', label: '⛓️ Imprisonment' },
    { value: 'suspend', label: '⛔ Service Suspension' },
    { value: 'acquittal', label: '✅ Acquittal' },
];

async function verdictFlow({ reportId, citizenid, name, plaintiff }) {
    const first = await modal({ title: 'Issue Verdict', okText: 'Next', fields: [
        { name: 'cid', label: 'Defendant citizen ID', required: true, value: citizenid || '', max: 50 },
        { name: 'type', label: 'Verdict type', type: 'select', options: VERDICT_TYPES },
    ] });
    if (!first) return false;
    const type = first.type;
    const fields = [];
    if (type === 'fine' || type === 'compensation') fields.push({ name: 'amount', label: 'Amount', type: 'number', required: true, min: 1, maxValue: S.config.maxFine });
    if (type === 'compensation') fields.push({ name: 'target', label: 'Injured party citizen ID', required: true, value: plaintiff || '', max: 50 });
    if (type === 'impound') fields.push({ name: 'plate', label: 'Vehicle plate', required: true, max: 12 });
    if (type === 'jail') fields.push({ name: 'months', label: 'Sentence (months)', type: 'number', required: true, min: 1, maxValue: S.config.maxJail });
    fields.push({ name: 'text', label: 'Verdict text', type: 'textarea', required: true, max: 400 });

    const label = VERDICT_TYPES.find((t) => t.value === type).label;
    const second = await modal({ title: `${label}${name ? ' - ' + name : ''}`, okText: 'Continue', fields });
    if (!second) return false;
    const summary = [label, `Defendant: ${first.cid}`, second.amount ? `Amount: ${money(second.amount)}` : '', second.target ? `Injured party: ${second.target}` : '',
        second.plate ? `Vehicle: ${second.plate}` : '', second.months ? `Sentence: ${second.months} months` : '', `\n${second.text}`].filter(Boolean).join('\n');
    if (!await confirmBox('Confirm Verdict', `${summary}\n\nThe verdict is executed immediately (it can be reversed from the Audit Log)`, true)) return false;

    const r = await call('issueVerdict', { reportId: reportId || null, citizenid: first.cid, type, amount: second.amount, target: second.target, plate: second.plate, months: second.months, text: second.text });
    if (r) toast(`Verdict #${r.id} issued and executed`, 'success');
    return !!r;
}

async function warrantFlow(citizenid, name) {
    const v = await modal({ title: `Warrant against ${name}`, okText: 'Issue', danger: true, text: `Sent to on-duty police immediately, valid for ${S.config.warrantHours || 72} hours`, fields: [
        { name: 'type', label: 'Warrant type', type: 'select', options: [{ value: 'arrest', label: '🚨 Arrest Warrant' }, { value: 'search', label: '🔍 Search Warrant' }] },
        { name: 'reason', label: 'Reason', required: true, max: 200 },
        { name: 'place', label: 'Location (for searches: house / vehicle / address)', max: 150 },
    ] });
    if (!v) return false;
    const r = await call('issueWarrant', citizenid, v.type, v.reason, v.place || '');
    if (r) toast(`Warrant #${r.id} issued and sent to police`, 'success');
    return !!r;
}

async function suspectFlow(citizenid, name) {
    const v = await modal({ title: `Flag ${name || citizenid} as a person of interest`, okText: 'Add', fields: [
        citizenid ? null : { name: 'cid', label: 'Citizen ID', required: true, max: 50 },
        { name: 'danger', label: 'Risk level', type: 'select', value: 'medium', options: [
            { value: 'low', label: 'Low' }, { value: 'medium', label: 'Medium' }, { value: 'high', label: 'High (instant police alert)' }] },
        { name: 'reason', label: 'Reason', required: true, max: 200 },
    ].filter(Boolean) });
    if (!v) return false;
    const r = await call('addSuspect', citizenid || v.cid, v.reason, v.danger);
    if (r) toast('Added to persons of interest', 'success');
    return !!r;
}

function caseLawyersCard(r, perms, reload) {
    const lawyers = arr(r.lawyers);
    return card(h('span', null, `⚖️ Counsel (${lawyers.length})`),
        perms.lawyers ? h('div', { class: 'actions', style: 'margin-bottom:10px' }, btn('➕ Assign Attorney', async () => {
            const v = await modal({ title: 'Assign Attorney to Case', text: 'They must hold a law license (granted from the Licenses tab)', fields: [
                { name: 'cid', label: 'Attorney citizen ID', required: true, max: 50 },
                { name: 'side', label: 'Represents', type: 'select', options: [{ value: 'plaintiff', label: `Plaintiff (${r.name})` }, { value: 'defendant', label: `Defendant (${r.defendantName || 'Not specified'})` }] },
            ] });
            if (v && await call('assignLawyer', r.id, v.cid, v.side)) { toast('Attorney assigned', 'success'); reload(); }
        }, 'small')) : null,
        lawyers.length ? h('div', { class: 'list' }, lawyers.map((l) => item({
            icon: '⚖️', title: `${l.name} (${l.citizenid})`, sub: `${l.sideLabel}\n${l.status ? l.status.text : ''}`,
            side: perms.lawyers ? btn('Remove', async () => {
                if (await confirmBox('Remove Attorney', `Remove ${l.name} from this case?`, true) && await call('removeLawyer', l.id)) { toast('Removed', 'success'); reload(); }
            }, 'small red') : null,
        }))) : empty('No attorneys assigned', '⚖️'));
}

function caseDocumentsCard(r, reload, canAdd) {
    const docs = arr(r.documents);
    return card(h('span', null, `📎 Documents (${docs.length})`),
        canAdd ? h('div', { class: 'actions', style: 'margin-bottom:10px' }, btn('➕ Add Document', async () => {
            const v = await modal({ title: 'New Document', fields: [
                { name: 'title', label: 'Title', required: true, max: 120 },
                { name: 'content', label: 'Content (text, image or video links...)', type: 'textarea', required: true, max: S.config.documentMax || 2000 },
            ] });
            if (v && await call('addDocument', r.id, v.title, v.content)) { toast('Document added', 'success'); reload(); }
        }, 'small')) : null,
        docs.length ? h('div', { class: 'list' }, docs.map((d) => h('div', { class: 'note' },
            h('div', { class: 'meta' }, `📎 ${d.title} | ${d.author} (${d.role}) - ${val(d.date)}`), h('div', { class: 'textblock', style: 'margin-top:6px' }, d.content)))) : empty('No documents', '📎'));
}

// ════════════════════════════════════════════════════════════════════════════
// Justice pages
// ════════════════════════════════════════════════════════════════════════════
PAGES.suspects = {
    title: 'Persons of Interest',
    async render() {
        const res = await call('getSuspects');
        if (!res) return null;
        const list = arr(res.suspects);
        S.info.suspects = list.length;
        const remove = async (s) => {
            if (await confirmBox('Remove Person of Interest', `Remove ${s.name} from the list?`) && await call('removeSuspect', s.id)) { toast('Removed', 'success'); render(); }
        };
        return card(h('span', null, `🕵️ Persons of Interest (${list.length})`),
            S.perms.suspects ? h('div', { class: 'actions', style: 'margin-bottom:12px' }, btn('➕ Add Person of Interest', async () => { if (await suspectFlow()) render(); }, 'primary')) : null,
            list.length ? h('div', { class: 'list' }, list.map((x) => suspectItem(x, 'profile', S.perms.suspects ? remove : null))) : empty('The list is empty', '🕵️'));
    },
};

PAGES.warrants = {
    title: 'Warrants',
    async render(activeOnly) {
        const onlyActive = activeOnly !== false;
        const res = await call('getWarrants', null, onlyActive);
        if (!res) return null;
        const list = arr(res.warrants);
        const chip = (v, label) => h('button', { class: 'chip' + (onlyActive === v ? ' active' : ''), onclick: () => { S.current.arg = v; render(); } }, label);
        return h('div', null,
            h('div', { class: 'chips' }, chip(true, '🚨 Active'), chip(false, 'All warrants')),
            card(null, list.length ? h('div', { class: 'list' }, list.map((w) => warrantItem(w, { profile: 'profile', cancel: S.perms.warrants, execute: !!S.info.judge, reload: render }))) : empty('No warrants', '🚨')));
    },
};

PAGES.policeRequests = {
    title: 'Police Requests',
    async render(filter) {
        const res = await call('getPoliceRequests', filter || null);
        if (!res) return null;
        S.info.policeRequests = res.pending;
        const list = arr(res.requests);
        const chip = (f, label) => h('button', { class: 'chip' + ((filter || null) === f ? ' active' : ''), onclick: () => { S.current.arg = f; render(); } }, label);
        const answer = async (q, approve) => {
            const v = await modal({ title: `${approve ? 'Approve' : 'Deny'} request #${q.id}`, okText: approve ? 'Approve' : 'Deny', danger: !approve,
                text: `${q.typeLabel} on ${q.name}\nFrom ${q.officer.name} (${q.officer.grade})\nReason: ${q.reason}`,
                fields: [{ name: 'note', label: 'Note to the officer (optional)', max: 200 }] });
            if (!v) return;
            const r = await call('answerPoliceRequest', q.id, approve, v.note || '');
            if (r) { toast(r.message, 'success', 6000); render(); }
        };
        return h('div', null,
            h('div', { class: 'chips' }, chip(null, 'All'), chip('pending', `⏳ Pending (${res.pending})`), chip('approved', '✅ Approved'), chip('rejected', '❌ Denied')),
            card(null, list.length ? h('div', { class: 'list' }, list.map((q) => item({
                icon: q.status === 'pending' ? '⏳' : q.status === 'approved' ? '✅' : '❌',
                title: `#${q.id} | ${q.typeLabel} | on: ${q.name} (${q.citizenid})`,
                sub: `👮 ${q.officer.name} - ${q.officer.job} - ${q.officer.grade}${q.officer.callsign ? ' [' + q.officer.callsign + ']' : ''} ${q.officer.status && q.officer.status.online ? '🟢' : '⚫'}\nReason: ${q.reason}${q.details ? '\nDetails: ' + q.details : ''}\n${val(q.date)}${q.answeredBy ? `\nResponse: ${q.statusLabel} by ${q.answeredBy}${q.answerNote ? ' - ' + q.answerNote : ''}` : ''}`,
                side: [
                    btn('Record', () => go('profile', q.citizenid), 'small'),
                    q.status === 'pending' ? btn('✅ Approve', () => answer(q, true), 'small green') : null,
                    q.status === 'pending' ? btn('❌ Deny', () => answer(q, false), 'small red') : null,
                ],
            }))) : empty('No requests', '🚓')));
    },
};

// ═════ Charts: single-hue column/bar, value at bar end, hover tooltip, and a table alternative ═════
function barChart({ title, data, unit = '', vertical = false }) {
    const rows = arr(data);
    const max = Math.max(1, ...rows.map((d) => Number(d.value) || 0));
    const fmt = (v) => `${Number(v).toLocaleString('en-US')}${unit}`;
    let showTable = false;
    const body = h('div');
    const tip = h('div', { class: 'chart-tip hidden' });

    const bind = (el, d) => {
        el.addEventListener('mousemove', (e) => {
            tip.textContent = `${d.label}: ${fmt(d.value)}`;
            tip.classList.remove('hidden');
            const box = body.getBoundingClientRect();
            tip.style.left = `${e.clientX - box.left}px`;
            tip.style.top = `${e.clientY - box.top - 34}px`;
        });
        el.addEventListener('mouseleave', () => tip.classList.add('hidden'));
    };

    const draw = () => {
        if (!rows.length) return body.replaceChildren(empty('No data', '📊'));
        if (showTable) {
            return body.replaceChildren(h('table', { class: 'chart-table' },
                h('tr', null, h('th', null, 'Item'), h('th', null, 'Value')),
                rows.map((d) => h('tr', null, h('td', null, d.label), h('td', null, fmt(d.value))))));
        }
        if (vertical) {
            const cols = rows.map((d) => {
                const hit = h('div', { class: 'col-hit' },
                    h('div', { class: 'col-value' }, Number(d.value) > 0 ? fmt(d.value) : ''),
                    h('div', { class: 'col-bar', style: `height:${(Number(d.value) / max) * 100}%` }));
                bind(hit, d);
                return h('div', { class: 'col' }, hit, h('div', { class: 'col-label' }, d.label));
            });
            return body.replaceChildren(h('div', { class: 'cols' }, cols), tip);
        }
        const bars = rows.map((d) => {
            const row = h('div', { class: 'hbar' },
                h('div', { class: 'hbar-label' }, d.label),
                h('div', { class: 'hbar-track' }, h('div', { class: 'hbar-fill', style: `width:${Math.max(1, (Number(d.value) / max) * 100)}%` }),
                    h('span', { class: 'hbar-value' }, fmt(d.value))));
            bind(row, d);
            return row;
        });
        body.replaceChildren(h('div', { class: 'hbars' }, bars), tip);
    };
    draw();
    const toggle = btn('Table', () => { showTable = !showTable; toggle.textContent = showTable ? 'Chart' : 'Table'; draw(); }, 'small');
    return h('div', { class: 'card chart' }, h('div', { class: 'card-title' }, title, h('span', { class: 'spacer' }), toggle), body);
}

PAGES.stats = {
    title: 'Statistics',
    async render() {
        const res = await call('getStats');
        if (!res) return null;
        const t = res.totals || {};
        return h('div', null,
            h('div', { class: 'grid stats', style: 'margin-bottom:14px' },
                stat('Total Cases', t.cases), stat('Active Verdicts', t.verdicts, 'red'),
                stat('Active Warrants', t.warrants, 'yellow'), stat('Persons of Interest', t.suspects, 'purple')),
            barChart({ title: '📈 New Cases per Week (last 8 weeks)', data: res.casesPerWeek, vertical: true }),
            h('div', { class: 'grid two' },
                barChart({ title: '📂 Most Common Case Types', data: res.caseTypes }),
                barChart({ title: '🔨 Active Verdicts by Type', data: res.verdictTypes })),
            h('div', { class: 'grid two' },
                barChart({ title: '👥 Staff Activity: Actions (30 days)', data: res.officers }),
                barChart({ title: '🕒 Duty Hours (last 7 days)', data: res.dutyHours, unit: ' h' })),
        );
    },
};

// ════════════════════════════════════════════════════════════════════════════
// Police pages
// ════════════════════════════════════════════════════════════════════════════
const REQUEST_TYPES = [
    { value: 'locate', label: '📍 Locate citizen now' },
    { value: 'bank', label: `🏦 Bank statement (${30}-minute clearance)` },
    { value: 'arrest_warrant', label: '🚨 Request arrest warrant' },
    { value: 'search_warrant', label: '🔍 Request search warrant' },
    { value: 'other', label: '📝 Other request' },
];

async function policeRequestFlow(citizenid, name) {
    const v = await modal({ title: `DOJ Clearance Request${name ? ' - ' + name : ''}`, okText: 'Submit Request',
        text: 'The request reaches the Department of Justice with your name, grade and callsign, and you get the answer instantly', fields: [
            citizenid ? null : { name: 'cid', label: 'Citizen ID', required: true, max: 50 },
            { name: 'type', label: 'Request type', type: 'select', options: REQUEST_TYPES.map((t) => t.value === 'bank' ? { ...t, label: `🏦 Bank statement (${S.config.grantMinutes || 30}-minute clearance)` } : t) },
            { name: 'reason', label: 'Reason', required: true, max: 200 },
            { name: 'details', label: 'Additional details (for searches: the location)', max: 200 },
        ].filter(Boolean) });
    if (!v) return false;
    const r = await call('policeRequest', citizenid || v.cid, v.type, v.reason, v.details || '');
    if (r) { toast(`Request #${r.id} sent to the Department of Justice`, 'success'); S.info.myPending = (S.info.myPending || 0) + 1; renderNav(); }
    return !!r;
}

PAGES.phome = {
    title: 'Police Department',
    async render() {
        const info = await call('tabletInfo');
        if (!info) return null;
        S.info = info;
        const quick = h('input', { placeholder: 'Name / citizen ID / phone / server ID' });
        const search = () => quick.value.trim() && go('psearch', quick.value.trim());
        quick.addEventListener('keydown', (e) => { if (e.key === 'Enter') search(); });
        return h('div', null,
            h('div', { class: 'grid stats', style: 'margin-bottom:14px' },
                stat('Active Warrants', info.warrants, 'red', S.perms.warrants ? () => go('pwarrants') : null),
                stat('Persons of Interest', info.suspects, 'yellow', S.perms.suspects ? () => go('psuspects') : null),
                stat('My Pending Requests', info.myPending, 'blue', S.perms.requests ? () => go('prequests') : null)),
            S.perms.search ? card('🔎 Citizen Lookup', h('div', { class: 'searchbar', style: 'margin:0' }, quick, btn('Search', search, 'primary'))) : null,
            card('ℹ️ Police Access', h('div', { class: 'item-sub' },
                'You can view: basic identity, licenses, vehicles, case and verdict history, warrants and persons of interest.\nLocating, bank statements and arrest/search warrants require a clearance request to the Department of Justice.')),
        );
    },
};

PAGES.psearch = {
    title: 'Citizen Lookup',
    async render(query) {
        const input = h('input', { placeholder: 'Name / citizen ID / phone / server ID', value: query || '' });
        const doSearch = () => { const q = input.value.trim(); if (q) { S.current.arg = q; render(); } };
        input.addEventListener('keydown', (e) => { if (e.key === 'Enter') doSearch(); });
        setTimeout(() => input.focus(), 50);
        let results = null;
        if (query) {
            const res = await call('policeSearch', query);
            const list = res ? arr(res.results) : [];
            results = res ? card(`Results (${list.length})`, list.length ? h('div', { class: 'list' }, list.map((c) => item({
                icon: dot(c.online), title: `${c.serverId ? `[${c.serverId}] ` : ''}${c.name}`,
                sub: `Citizen ID: ${c.citizenid} | ${val(c.job)}`, onclick: () => go('pprofile', c.citizenid),
            }))) : empty('No results', '🔍')) : null;
        }
        return h('div', null, h('div', { class: 'searchbar' }, input, btn('Search', doSearch, 'primary')), results || empty('Type in the search box', '🔎'));
    },
};

PAGES.pprofile = {
    title: (cid) => `Citizen Record ${cid}`,
    async render(cid) {
        const res = await call('policeProfile', cid);
        if (!res) return null;
        const p = res.profile;
        const court = { suspect: p.suspect, warrants: p.warrants, verdicts: p.verdicts };
        return h('div', null,
            h('div', { class: 'profile-head' }, h('div', { class: 'avatar' }, (p.name || '?').slice(0, 1)),
                h('div', { style: 'flex:1;min-width:0' }, h('div', { class: 'profile-name' }, p.name),
                    h('div', { class: 'profile-meta' }, badge(p.status ? p.status.text : '-', p.status && p.status.online ? 'green' : 'gray'), badge(`Citizen ID: ${p.citizenid}`), badge(`${p.job.label} - ${p.job.grade}`, 'blue')))),
            p.suspended ? h('div', { class: 'alert red' }, '⛔ This citizen\'s services are suspended by order of the Department of Justice') : null,
            courtAlerts(court),
            S.perms.requests ? h('div', { class: 'actions', style: 'margin-bottom:14px' }, btn('📨 Request DOJ Clearance', () => policeRequestFlow(p.citizenid, p.name), 'primary')) : null,
            card('🪪 Identity', kv([['Name', p.name], ['Citizen ID', p.citizenid], ['Date of Birth', p.birthdate], ['Sex', gender(p.gender)], ['Nationality', p.nationality], ['Phone', p.phone], ['Job', `${p.job.label} - ${p.job.grade}`]])),
            p.bank ? card(`🏦 Bank Statement (clearance valid ${p.bank.remaining} min)`, h('div', { class: 'grid stats' }, stat('Bank', money(p.bank.bank), 'green'), stat('Cash', money(p.bank.cash)))) : null,
            card('📄 Licenses', arr(p.licenses).length ? h('div', { class: 'list' }, arr(p.licenses).map((l) => item({ icon: l.active ? '✅' : '❌', title: l.label, sub: l.active ? 'Valid' : 'Not held' }))) : empty('No licenses')),
            p.vehicles ? card(`🚗 Vehicles (${arr(p.vehicles).length})`, arr(p.vehicles).length ? h('div', { class: 'list' }, arr(p.vehicles).map((v) => item({ icon: '🚗', title: `${v.plate} | ${v.label}`, sub: v.state }))) : empty('No registered vehicles')) : null,
            card(`⚖️ Case History (${arr(p.cases).length})`, arr(p.cases).length ? h('div', { class: 'list' }, arr(p.cases).map((c) => item({ icon: '⚖️', title: `#${c.id} | ${c.title}`, sub: `${c.role} | ${val(c.caseType)} | ${c.status} | ${val(c.date)}` }))) : empty('No cases', '⚖️')),
            card(`🔨 Verdicts (${arr(p.verdicts).length})`, arr(p.verdicts).length ? h('div', { class: 'list' }, arr(p.verdicts).map(verdictItem)) : empty('No verdicts', '🔨')),
            card(`🚨 Warrants (${arr(p.warrants).length})`, arr(p.warrants).length ? h('div', { class: 'list' }, arr(p.warrants).map((w) => warrantItem(w, { execute: S.perms.executeWarrant, reload: render }))) : empty('No warrants', '🚨')),
        );
    },
};

PAGES.pwarrants = {
    title: 'Active Warrants',
    async render() {
        const res = await call('policeWarrants');
        if (!res) return null;
        const list = arr(res.warrants);
        S.info.warrants = list.length;
        return card(`🚨 Active (${list.length})`, list.length ? h('div', { class: 'list' }, list.map((w) => warrantItem(w, { profile: 'pprofile', execute: S.perms.executeWarrant, reload: render }))) : empty('No active warrants', '✅'));
    },
};

PAGES.psuspects = {
    title: 'Persons of Interest',
    async render() {
        const res = await call('policeSuspects');
        if (!res) return null;
        const list = arr(res.suspects);
        return card(`🕵️ Persons of Interest (${list.length})`, list.length ? h('div', { class: 'list' }, list.map((x) => suspectItem(x, 'pprofile'))) : empty('The list is empty', '🕵️'));
    },
};

PAGES.prequests = {
    title: 'My DOJ Requests',
    async render() {
        const res = await call('policeMyRequests');
        if (!res) return null;
        const list = arr(res.requests);
        S.info.myPending = list.filter((q) => q.status === 'pending').length;
        return card(h('span', null, `📨 My Requests (${list.length})`),
            h('div', { class: 'actions', style: 'margin-bottom:12px' }, btn('➕ New Request', async () => { if (await policeRequestFlow()) render(); }, 'primary')),
            list.length ? h('div', { class: 'list' }, list.map((q) => item({
                icon: q.status === 'pending' ? '⏳' : q.status === 'approved' ? '✅' : '❌',
                title: `#${q.id} | ${q.typeLabel} | ${q.name} (${q.citizenid})`,
                sub: `Reason: ${q.reason}\n${val(q.date)}${q.answeredBy ? `\nResponse: ${q.statusLabel} by ${q.answeredBy}${q.answerNote ? ' - ' + q.answerNote : ''}` : ''}`,
                side: [badge(q.statusLabel, q.status === 'pending' ? 'yellow' : q.status === 'approved' ? 'green' : 'red'), btn('Record', () => go('pprofile', q.citizenid), 'small')],
            }))) : empty('You have not sent any requests', '📨'));
    },
};

// ════════════════════════════════════════════════════════════════════════════
// Attorney pages
// ════════════════════════════════════════════════════════════════════════════
PAGES.lcases = {
    title: 'My Cases',
    async render() {
        const res = await call('lawyerCases');
        if (!res) return null;
        const list = arr(res.cases);
        return card(`💼 Assigned Cases (${list.length})`, list.length ? h('div', { class: 'list' }, list.map((c) => item({
            icon: '⚖️', title: `#${c.id} | ${c.title}`, sub: `Client: ${c.client} (${c.sideLabel}) | ${val(c.caseType)} | ${c.date}`,
            side: badge(c.statusLabel, STATUS[c.status] ? STATUS[c.status][1] : ''), onclick: () => go('lcase', c.id),
        }))) : empty('You have not been assigned to any case yet', '💼'));
    },
};

PAGES.lcase = {
    title: (id) => `Case #${id}`,
    async render(id) {
        const res = await call('lawyerCase', id);
        if (!res) return null;
        const c = res.case;
        return h('div', null,
            h('div', { class: 'profile-head' }, h('div', { class: 'avatar' }, '⚖️'),
                h('div', null, h('div', { class: 'profile-name' }, c.title),
                    h('div', { class: 'profile-meta' }, badge(c.statusLabel, STATUS[c.status] ? STATUS[c.status][1] : ''), badge(val(c.caseType), 'blue'), badge(c.date, 'gray')))),
            h('div', { class: 'actions', style: 'margin-bottom:14px' }, btn('📝 Add Note', async () => {
                const v = await modal({ title: 'Attorney Note', fields: [{ name: 'note', label: 'Note', type: 'textarea', required: true, max: S.config.noteMax || 500 }] });
                if (v && await call('lawyerNote', c.id, v.note)) { toast('Note added', 'success'); render(); }
            })),
            card('👥 Parties', kv([['Plaintiff', c.plaintiff], ['Defendant', c.defendant]])),
            card('📄 Complaint', h('div', { class: 'textblock' }, c.report)),
            c.witnesses && c.witnesses !== '' ? card('👥 Witnesses', h('div', { class: 'textblock' }, c.witnesses)) : null,
            c.evidence && c.evidence !== '' ? card('🔍 Evidence', h('div', { class: 'textblock' }, c.evidence)) : null,
            caseDocumentsCard(c, () => render(), true),
            arr(c.verdicts).length ? card('🔨 Verdicts', h('div', { class: 'list' }, arr(c.verdicts).map(verdictItem))) : null,
            card(`🗒️ Notes (${arr(c.notes).length})`, arr(c.notes).length ? h('div', { class: 'list' }, arr(c.notes).map((n) => h('div', { class: 'note' }, h('div', { class: 'meta' }, `${n.author} - ${val(n.date)}`), n.note))) : empty('No notes')),
        );
    },
};

// ════════════════════════════════════════════════════════════════════════════
// 💰 Department finance office
// ════════════════════════════════════════════════════════════════════════════
PAGES.finance = {
    title: 'Finance Office',
    async render(job) {
        const res = await call('financeInfo', job || null);
        if (!res) return null;
        $('page-title').textContent = `Finance Office: ${res.label}`;
        const sectorChips = arr(res.sectors).length ? h('div', { class: 'chips' }, arr(res.sectors).map((x) =>
            h('button', { class: 'chip' + (x.job === res.job ? ' active' : ''), onclick: () => { S.current.arg = x.job; render(); } }, x.label))) : null;
        const reload = () => render();
        const act = async (type) => {
            const deposit = type === 'deposit';
            const v = await modal({
                title: deposit ? `Deposit to ${res.label}` : `Withdraw from ${res.label}`,
                text: deposit ? `From your bank account (your balance: ${money(res.myBank)})` : `To your bank account (department balance: ${money(res.balance)})`,
                okText: 'Continue',
                fields: [
                    { name: 'amount', label: 'Amount', type: 'number', required: true, min: 1, maxValue: Math.min(res.maxPerTransaction, deposit ? res.myBank : res.balance) },
                    { name: 'reason', label: 'Reason', required: true, max: 150 },
                ],
            });
            if (!v || !await confirmBox('Confirm', `${deposit ? 'Deposit' : 'Withdraw'} ${money(v.amount)}\nReason: ${v.reason}`, !deposit)) return;
            const r = await call(deposit ? 'financeDeposit' : 'financeWithdraw', v.amount, v.reason, res.job);
            if (r) { toast(`Done. Department balance: ${money(r.balance)}`, 'success'); reload(); }
        };
        const history = arr(res.history);
        return h('div', null,
            sectorChips,
            h('div', { class: 'grid stats', style: 'margin-bottom:14px' },
                stat(`${res.label} Balance`, money(res.balance), 'green'),
                stat('Your Bank Balance', money(res.myBank), 'gold'),
                stat('Limit per Transaction', money(res.maxPerTransaction), 'blue')),
            h('div', { class: 'actions', style: 'margin-bottom:14px' },
                h('button', { class: 'btn primary', disabled: res.myBank <= 0 || null, onclick: () => act('deposit') }, '⬆️ Deposit to Department'),
                h('button', { class: 'btn red', disabled: res.balance <= 0 || null, onclick: () => act('withdraw') }, '⬇️ Withdraw from Department')),
            card(`🧾 Transaction Ledger (${history.length})`, history.length ? h('div', { class: 'list' }, history.map((t) => item({
                icon: t.type === 'deposit' ? '⬆️' : '⬇️',
                title: `${t.typeLabel} ${money(t.amount)} | ${t.officer}${t.grade ? ' - ' + t.grade : ''}`,
                sub: `${t.reason}\n${val(t.date)}${t.balance != null ? ' | Balance after: ' + money(t.balance) : ''}`,
            }))) : empty('No transactions', '🧾')),
            h('div', { class: 'item-sub' }, `Balance source: ${res.provider}`),
        );
    },
};

// ═════ Live notifications (sound + alert) ═════
function chime() {
    try {
        const ctx = S.audio || (S.audio = new (window.AudioContext || window.webkitAudioContext)());
        [[880, 0], [1320, 0.13]].forEach(([freq, delay]) => {
            const o = ctx.createOscillator();
            const g = ctx.createGain();
            o.type = 'sine';
            o.frequency.value = freq;
            g.gain.setValueAtTime(0.0001, ctx.currentTime + delay);
            g.gain.exponentialRampToValueAtTime(0.18, ctx.currentTime + delay + 0.02);
            g.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + delay + 0.35);
            o.connect(g).connect(ctx.destination);
            o.start(ctx.currentTime + delay);
            o.stop(ctx.currentTime + delay + 0.4);
        });
    } catch (e) { /* sound is optional */ }
}

function onLiveEvent(ev) {
    if (!ev || typeof ev !== 'object') return;
    chime();
    toast(`${ev.title || ''}${ev.text ? '\n' + ev.text : ''}`, 'info', 8000);
    if (ev.type === 'new_case') S.info.newReports = (Number(S.info.newReports) || 0) + 1;
    if (ev.type === 'police_request') S.info.policeRequests = (Number(S.info.policeRequests) || 0) + 1;
    if (ev.type === 'warrant' && S.role === 'police') S.info.warrants = (Number(S.info.warrants) || 0) + 1;
    if (ev.type === 'request_answered' && S.role === 'police') S.info.myPending = Math.max(0, (Number(S.info.myPending) || 0) - 1);
    renderNav();
    const page = S.current && S.current.page;
    const refreshOn = { new_case: ['reports', 'home'], police_request: ['policeRequests'], warrant: ['pwarrants', 'phome'], request_answered: ['prequests'], document: ['report'], finance: ['finance'] };
    if ((refreshOn[ev.type] || []).includes(page) && !$('modal-root').children.length) render();
}

// ═════ Open and close ═════
function renderMe() {
    const roleLabel = S.info && S.info.judge ? '👑 Judge - full access to State Records' : ({ justice: '⚖️ Department of Justice', police: '🚓 Police Department', lawyer: '💼 Attorney', sector: '💰 Department Manager' }[S.role] || '');
    $('me').replaceChildren(h('b', null, S.me.name || '-'), h('br'), h('span', null, `${val(S.me.job)} - ${val(S.me.grade)}`), h('br'), h('span', { class: 'role-tag' }, roleLabel));
}

function openTablet(data) {
    S.open = true;
    S.role = data.role || (data.info && data.info.role) || 'justice';
    S.info = data.info || {};
    S.perms = (data.info && data.info.perms) || {};
    S.me = data.me || {};
    S.config = data.config || {};
    S.stack = [];
    S.logsPage = 0;
    S.profileTab = null;
    renderMe();
    $('app').classList.remove('hidden');
    const allowed = currentNav().map((n) => n.page);
    const start = data.page && PAGES[data.page] && (S.role === 'justice' || allowed.includes(data.page)) ? data.page : homePage();
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
    else if (d.action === 'event' && S.open) onLiveEvent(d.event);
});

document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || !S.open) return;
    if ($('modal-root').children.length) closeModal();
    else closeTablet();
});

$('btn-close').addEventListener('click', closeTablet);
$('btn-back').addEventListener('click', back);
$('btn-refresh').addEventListener('click', refresh);
