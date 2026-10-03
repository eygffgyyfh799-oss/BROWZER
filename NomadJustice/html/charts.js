'use strict';
/* ════════════════════════════════════════════════════════════════════════════
   NomadJustice - interactive D3 charts
   Single series = stone grey (logo colour). Categorical slots (validated on the
   tablet surface #191917): blue, orange, aqua. Every chart has a hover/focus
   tooltip, animated entry and a table view. Labels are set with textContent only.
   ════════════════════════════════════════════════════════════════════════════ */

const Charts = (() => {
    const MARK = '#b8b2a1';
    const MARK_HOVER = '#d8d3c4';
    const SURFACE = '#191917';
    const GRID = '#2c2b27';
    const MUTED = '#8f8b80';
    const CATEGORICAL = ['#3987e5', '#d95926', '#199e70'];
    const DURATION = 650;

    const num = (v) => Number(v) || 0;
    const fmt = (v, unit = '') => `${num(v).toLocaleString('en-US')}${unit}`;
    const rowsOf = (data) => (Array.isArray(data) ? data : data && typeof data === 'object' ? Object.values(data) : [])
        .map((d) => ({ label: String(d.label ?? ''), value: num(d.value), color: d.color }));

    // Shared tooltip: value strong, label secondary, short line key
    function tooltip(host) {
        const tip = document.createElement('div');
        tip.className = 'viz-tip hidden';
        const key = document.createElement('span'); key.className = 'viz-tip-key';
        const value = document.createElement('b');
        const label = document.createElement('span'); label.className = 'viz-tip-label';
        tip.append(key, value, label);
        host.append(tip);
        return {
            show(x, y, d, unit, color) {
                key.style.background = color || MARK;
                value.textContent = fmt(d.value, unit);
                label.textContent = d.label;
                tip.classList.remove('hidden');
                const w = host.clientWidth;
                tip.style.left = `${Math.max(60, Math.min(w - 60, x))}px`;
                tip.style.top = `${y}px`;
            },
            hide() { tip.classList.add('hidden'); },
        };
    }

    // Redraw on resize; draw once the host has a width (it may be built before it is in the DOM)
    function responsive(host, draw) {
        let last = 0;
        const run = () => {
            const w = Math.floor(host.clientWidth);
            if (w > 0 && w !== last) { last = w; draw(w); }
        };
        if (typeof ResizeObserver === 'function') new ResizeObserver(run).observe(host);
        requestAnimationFrame(run);
    }

    // Column with a 4px rounded top anchored to a square baseline
    function topRounded(x, y, w, hgt, r = 4) {
        if (hgt <= 0) return `M${x},${y}h${w}v0h${-w}Z`;
        r = Math.min(r, w / 2, hgt);
        return `M${x},${y + hgt}V${y + r}Q${x},${y} ${x + r},${y}H${x + w - r}Q${x + w},${y} ${x + w},${y + r}V${y + hgt}Z`;
    }
    function rightRounded(x, y, w, hgt, r = 4) {
        if (w <= 0) return `M${x},${y}v${hgt}h0v${-hgt}Z`;
        r = Math.min(r, hgt / 2, w);
        return `M${x},${y}H${x + w - r}Q${x + w},${y} ${x + w},${y + r}V${y + hgt - r}Q${x + w},${y + hgt} ${x + w - r},${y + hgt}H${x}Z`;
    }

    function yGrid(svg, y, width, left) {
        const ticks = y.ticks(3);
        const g = svg.append('g').attr('class', 'viz-grid');
        g.selectAll('line').data(ticks).join('line')
            .attr('x1', left).attr('x2', width).attr('y1', (t) => y(t)).attr('y2', (t) => y(t))
            .attr('stroke', GRID).attr('stroke-width', 1);
        g.selectAll('text').data(ticks).join('text')
            .attr('x', left - 6).attr('y', (t) => y(t)).attr('dy', '0.32em').attr('text-anchor', 'end')
            .attr('fill', MUTED).attr('font-size', 10.5).text((t) => d3.format('~s')(t));
    }

    // ═════ Vertical columns ═════
    function column(host, data, { unit = '', height = 210 } = {}) {
        const rows = rowsOf(data);
        const tip = tooltip(host);
        responsive(host, (width) => {
            d3.select(host).select('svg').remove();
            const m = { top: 22, right: 6, bottom: 26, left: 34 };
            const svg = d3.select(host).insert('svg', ':first-child').attr('width', width).attr('height', height).attr('role', 'img');
            const x = d3.scaleBand().domain(rows.map((d, i) => i)).range([m.left, width - m.right]).paddingInner(0.28).paddingOuter(0.12);
            const y = d3.scaleLinear().domain([0, Math.max(1, d3.max(rows, (d) => d.value))]).nice().range([height - m.bottom, m.top]);
            yGrid(svg, y, width - m.right, m.left);
            const bw = Math.min(28, x.bandwidth());
            const off = (x.bandwidth() - bw) / 2;
            const base = y(0);

            const bars = svg.append('g').selectAll('path').data(rows).join('path')
                .attr('fill', MARK)
                .attr('d', (d, i) => topRounded(x(i) + off, base, bw, 0));
            bars.transition().duration(DURATION).delay((d, i) => i * 45).ease(d3.easeCubicOut)
                .attrTween('d', (d, i) => {
                    const target = base - y(d.value);
                    return (t) => topRounded(x(i) + off, base - target * t, bw, target * t);
                });

            // Selective direct labels: the highest and the latest value
            const maxIdx = d3.maxIndex(rows, (d) => d.value);
            svg.append('g').selectAll('text').data(rows).join('text')
                .filter((d, i) => d.value > 0 && (i === maxIdx || i === rows.length - 1))
                .attr('x', (d, i) => x(rows.indexOf(d)) + x.bandwidth() / 2).attr('y', (d) => y(d.value) - 6)
                .attr('text-anchor', 'middle').attr('fill', '#ecebe6').attr('font-size', 11).attr('font-weight', 700)
                .attr('opacity', 0).text((d) => fmt(d.value, unit))
                .transition().delay(DURATION).duration(250).attr('opacity', 1);

            svg.append('g').selectAll('text').data(rows).join('text')
                .attr('x', (d, i) => x(i) + x.bandwidth() / 2).attr('y', height - 8).attr('text-anchor', 'middle')
                .attr('fill', MUTED).attr('font-size', 10.5)
                .text((d) => (d.label.length > 11 ? d.label.slice(0, 10) + '…' : d.label));

            // Hit targets: the whole band, keyboard focusable
            svg.append('g').selectAll('rect').data(rows).join('rect')
                .attr('x', (d, i) => x(i) - (x.step() - x.bandwidth()) / 2).attr('width', x.step())
                .attr('y', m.top).attr('height', height - m.top - m.bottom)
                .attr('fill', 'transparent').attr('tabindex', 0).attr('class', 'viz-hit')
                .on('pointerenter focus', function (event, d) {
                    const i = rows.indexOf(d);
                    bars.filter((b, j) => j === i).attr('fill', MARK_HOVER);
                    tip.show(x(i) + x.bandwidth() / 2, y(d.value) - 10, d, unit);
                })
                .on('pointerleave blur', () => { bars.attr('fill', MARK); tip.hide(); });
        });
    }

    // ═════ Line + area over time with a snapping crosshair ═════
    function area(host, data, { unit = '', height = 210 } = {}) {
        const rows = rowsOf(data);
        const tip = tooltip(host);
        responsive(host, (width) => {
            d3.select(host).select('svg').remove();
            const m = { top: 20, right: 14, bottom: 26, left: 34 };
            const svg = d3.select(host).insert('svg', ':first-child').attr('width', width).attr('height', height).attr('role', 'img');
            const x = d3.scalePoint().domain(rows.map((d, i) => i)).range([m.left + 4, width - m.right]);
            const y = d3.scaleLinear().domain([0, Math.max(1, d3.max(rows, (d) => d.value))]).nice().range([height - m.bottom, m.top]);
            yGrid(svg, y, width - m.right, m.left);

            const gradId = `viz-grad-${Math.random().toString(36).slice(2, 8)}`;
            const grad = svg.append('defs').append('linearGradient').attr('id', gradId).attr('x1', 0).attr('x2', 0).attr('y1', 0).attr('y2', 1);
            grad.append('stop').attr('offset', '0%').attr('stop-color', MARK).attr('stop-opacity', 0.28);
            grad.append('stop').attr('offset', '100%').attr('stop-color', MARK).attr('stop-opacity', 0);

            const areaGen = d3.area().x((d, i) => x(i)).y0(y(0)).y1((d) => y(d.value)).curve(d3.curveMonotoneX);
            const lineGen = d3.line().x((d, i) => x(i)).y((d) => y(d.value)).curve(d3.curveMonotoneX);

            svg.append('path').datum(rows).attr('fill', `url(#${gradId})`).attr('d', areaGen)
                .attr('opacity', 0).transition().duration(DURATION).attr('opacity', 1);
            const line = svg.append('path').datum(rows).attr('fill', 'none').attr('stroke', MARK).attr('stroke-width', 2)
                .attr('stroke-linejoin', 'round').attr('stroke-linecap', 'round').attr('d', lineGen);
            const len = line.node().getTotalLength ? line.node().getTotalLength() : 0;
            if (len) {
                line.attr('stroke-dasharray', `${len} ${len}`).attr('stroke-dashoffset', len)
                    .transition().duration(DURATION + 300).ease(d3.easeCubicOut).attr('stroke-dashoffset', 0)
                    .on('end', () => line.attr('stroke-dasharray', null));
            }

            // X labels: thin out when crowded
            const every = Math.ceil(rows.length / Math.max(2, Math.floor((width - m.left) / 64)));
            svg.append('g').selectAll('text').data(rows).join('text')
                .filter((d, i) => i % every === 0 || i === rows.length - 1)
                .attr('x', (d) => x(rows.indexOf(d))).attr('y', height - 8).attr('text-anchor', 'middle')
                .attr('fill', MUTED).attr('font-size', 10.5).text((d) => d.label);

            // Direct label on the latest point
            if (rows.length) {
                const last = rows[rows.length - 1];
                svg.append('text').attr('x', x(rows.length - 1)).attr('y', y(last.value) - 10).attr('text-anchor', 'end')
                    .attr('fill', '#ecebe6').attr('font-size', 11).attr('font-weight', 700).text(fmt(last.value, unit))
                    .attr('opacity', 0).transition().delay(DURATION).attr('opacity', 1);
            }

            const cross = svg.append('line').attr('stroke', MUTED).attr('stroke-width', 1).attr('y1', m.top).attr('y2', height - m.bottom).attr('opacity', 0);
            const focus = svg.append('circle').attr('r', 5).attr('fill', MARK).attr('stroke', SURFACE).attr('stroke-width', 2).attr('opacity', 0);

            const pick = (px) => {
                let best = 0, dist = Infinity;
                rows.forEach((d, i) => { const dd = Math.abs(x(i) - px); if (dd < dist) { dist = dd; best = i; } });
                return best;
            };
            const show = (i) => {
                const d = rows[i];
                if (!d) return;
                cross.attr('x1', x(i)).attr('x2', x(i)).attr('opacity', 1);
                focus.attr('cx', x(i)).attr('cy', y(d.value)).attr('opacity', 1);
                tip.show(x(i), y(d.value) - 12, d, unit);
            };
            let kbd = rows.length - 1;
            svg.append('rect').attr('x', m.left).attr('y', m.top).attr('width', width - m.left - m.right).attr('height', height - m.top - m.bottom)
                .attr('fill', 'transparent').attr('tabindex', 0).attr('class', 'viz-hit')
                .on('pointermove', (event) => show(pick(d3.pointer(event)[0])))
                .on('focus', () => show(kbd))
                .on('keydown', (event) => {
                    if (event.key === 'ArrowLeft') kbd = Math.max(0, kbd - 1);
                    else if (event.key === 'ArrowRight') kbd = Math.min(rows.length - 1, kbd + 1);
                    else return;
                    event.preventDefault();
                    show(kbd);
                })
                .on('pointerleave blur', () => { cross.attr('opacity', 0); focus.attr('opacity', 0); tip.hide(); });
        });
    }

    // ═════ Horizontal bars (label left, value at bar end) ═════
    function hbar(host, data, { unit = '' } = {}) {
        const rows = rowsOf(data);
        const tip = tooltip(host);
        const rowH = 26;
        const height = rows.length * rowH + 6;
        responsive(host, (width) => {
            d3.select(host).select('svg').remove();
            const labelW = Math.min(150, Math.max(90, width * 0.3));
            const valueW = 70;
            const svg = d3.select(host).insert('svg', ':first-child').attr('width', width).attr('height', height).attr('role', 'img');
            const x = d3.scaleLinear().domain([0, Math.max(1, d3.max(rows, (d) => d.value))]).range([0, width - labelW - valueW]);
            const g = svg.append('g').selectAll('g').data(rows).join('g').attr('transform', (d, i) => `translate(0,${i * rowH + 3})`);

            g.append('text').attr('x', labelW - 10).attr('y', rowH / 2 - 2).attr('dy', '0.32em').attr('text-anchor', 'end')
                .attr('fill', '#ecebe6').attr('font-size', 12)
                .text((d) => (d.label.length > 20 ? d.label.slice(0, 19) + '…' : d.label));
            const bars = g.append('path').attr('fill', MARK).attr('d', () => rightRounded(labelW, 3, 0, rowH - 10));
            bars.transition().duration(DURATION).delay((d, i) => i * 40).ease(d3.easeCubicOut)
                .attrTween('d', (d) => (t) => rightRounded(labelW, 3, Math.max(2, x(d.value)) * t, rowH - 10));
            const values = g.append('text').attr('y', rowH / 2 - 2).attr('dy', '0.32em').attr('fill', MUTED)
                .attr('font-size', 11.5).attr('font-weight', 700).attr('x', labelW + 6).text((d) => fmt(d.value, unit));
            values.transition().duration(DURATION).delay((d, i) => i * 40).ease(d3.easeCubicOut).attr('x', (d) => labelW + Math.max(2, x(d.value)) + 6);

            g.append('rect').attr('x', 0).attr('y', 0).attr('width', width).attr('height', rowH)
                .attr('fill', 'transparent').attr('tabindex', 0).attr('class', 'viz-hit')
                .on('pointerenter focus', function (event, d) {
                    bars.filter((b) => b === d).attr('fill', MARK_HOVER);
                    tip.show(labelW + x(d.value) / 2, rows.indexOf(d) * rowH - 8, d, unit);
                })
                .on('pointerleave blur', () => { bars.attr('fill', MARK); tip.hide(); });
        });
    }

    // ═════ Donut: part-to-whole for a few categories, legend toggles slices ═════
    function donut(host, data, { unit = '', size = 190 } = {}) {
        const all = rowsOf(data).map((d, i) => ({ ...d, color: d.color || CATEGORICAL[i % CATEGORICAL.length], on: true }));
        const tip = tooltip(host);
        host.classList.add('is-donut');
        const wrap = document.createElement('div'); wrap.className = 'viz-donut';
        const legend = document.createElement('div'); legend.className = 'viz-legend';
        host.append(wrap, legend);

        const svg = d3.select(wrap).append('svg').attr('width', size).attr('height', size).attr('role', 'img');
        const g = svg.append('g').attr('transform', `translate(${size / 2},${size / 2})`);
        const r = size / 2 - 6;
        const arc = d3.arc().innerRadius(r * 0.62).outerRadius(r).cornerRadius(3);
        const arcHover = d3.arc().innerRadius(r * 0.62).outerRadius(r + 5).cornerRadius(3);
        const pie = d3.pie().value((d) => (d.on ? d.value : 0)).sort(null).padAngle(0.02);
        const centerValue = g.append('text').attr('text-anchor', 'middle').attr('dy', '-0.1em').attr('fill', '#ecebe6').attr('font-size', 24).attr('font-weight', 800);
        const centerLabel = g.append('text').attr('text-anchor', 'middle').attr('dy', '1.5em').attr('fill', MUTED).attr('font-size', 11.5);
        const total = () => d3.sum(all, (d) => (d.on ? d.value : 0));
        const setCenter = (value, label) => { centerValue.text(fmt(value, unit)); centerLabel.text(label); };
        let current = new Map();

        const draw = () => {
            const arcs = pie(all);
            setCenter(total(), 'Total');
            g.selectAll('path.slice').data(arcs, (d) => d.data.label).join(
                (enter) => enter.append('path').attr('class', 'slice viz-hit').attr('tabindex', 0)
                    .attr('fill', (d) => d.data.color).attr('stroke', SURFACE).attr('stroke-width', 2)
                    .each(function (d) { current.set(d.data.label, { startAngle: d.startAngle, endAngle: d.startAngle }); }),
            )
                .on('pointerenter focus', function (event, d) {
                    if (!d.data.on) return;
                    d3.select(this).transition().duration(150).attr('d', arcHover(d));
                    setCenter(d.data.value, d.data.label);
                    const [cx, cy] = arc.centroid(d);
                    tip.show(size / 2 + cx, size / 2 + cy - 14, d.data, unit, d.data.color);
                })
                .on('pointerleave blur', function (event, d) {
                    d3.select(this).transition().duration(150).attr('d', arc(d));
                    setCenter(total(), 'Total');
                    tip.hide();
                })
                .transition().duration(DURATION).ease(d3.easeCubicOut)
                .attrTween('d', function (d) {
                    const from = current.get(d.data.label) || d;
                    const i = d3.interpolate(from, d);
                    current.set(d.data.label, { startAngle: d.startAngle, endAngle: d.endAngle });
                    return (t) => arc(i(t));
                });

            const sum = total() || 1;
            legend.replaceChildren(...all.map((d) => {
                const row = document.createElement('button');
                row.className = 'viz-legend-row' + (d.on ? '' : ' off');
                row.title = d.on ? 'Click to hide' : 'Click to show';
                const sw = document.createElement('span'); sw.className = 'viz-swatch'; sw.style.background = d.color;
                const name = document.createElement('span'); name.className = 'viz-legend-name'; name.textContent = d.label;
                const v = document.createElement('b'); v.textContent = fmt(d.value, unit);
                const pct = document.createElement('span'); pct.className = 'viz-legend-pct';
                pct.textContent = d.on ? `${Math.round((d.value / sum) * 100)}%` : 'hidden';
                row.append(sw, name, v, pct);
                row.addEventListener('click', () => {
                    if (d.on && all.filter((x) => x.on).length === 1) return;
                    d.on = !d.on;
                    draw();
                });
                return row;
            }));
        };
        draw();
    }

    // Count-up animation for headline numbers
    function countUp(el, to, ms = 700) {
        const target = num(to);
        if (!target || typeof requestAnimationFrame !== 'function') { el.textContent = fmt(target); return; }
        const start = performance.now();
        const ease = (t) => 1 - Math.pow(1 - t, 3);
        const step = (now) => {
            const t = Math.min(1, (now - start) / ms);
            el.textContent = fmt(Math.round(target * ease(t)));
            if (t < 1) requestAnimationFrame(step);
        };
        requestAnimationFrame(step);
    }

    return { column, area, hbar, donut, countUp, available: () => typeof d3 !== 'undefined', CATEGORICAL };
})();
