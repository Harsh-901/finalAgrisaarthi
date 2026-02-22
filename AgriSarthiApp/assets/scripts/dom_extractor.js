(function () {
    'use strict';

    // ── Helpers ──────────────────────────────────────────────────────────────

    function resolveLabel(el) {
        // Strategy 1: <label for="id">
        if (el.id) {
            const lbl = document.querySelector('label[for="' + el.id + '"]');
            if (lbl && lbl.textContent.trim()) return lbl.textContent.trim();
        }
        // Strategy 2: aria-label
        if (el.getAttribute('aria-label')) return el.getAttribute('aria-label').trim();
        // Strategy 3: aria-labelledby
        const lblId = el.getAttribute('aria-labelledby');
        if (lblId) {
            const ref = document.getElementById(lblId);
            if (ref && ref.textContent.trim()) return ref.textContent.trim();
        }
        // Strategy 4: ancestor <label>
        let p = el.parentElement;
        while (p) {
            if (p.tagName === 'LABEL' && p.textContent.trim()) return p.textContent.trim();
            p = p.parentElement;
        }
        // Strategy 5: placeholder
        if (el.placeholder && el.placeholder.trim()) return el.placeholder.trim();
        // Strategy 6: title
        if (el.title && el.title.trim()) return el.title.trim();
        // Strategy 7: name / id fallback
        return (el.name || el.id || '').replace(/[-_]/g, ' ').trim();
    }

    function resolveSection(el) {
        let p = el.parentElement;
        while (p && p !== document.body) {
            if (p.tagName === 'FIELDSET') {
                const legend = p.querySelector('legend');
                if (legend && legend.textContent.trim()) return legend.textContent.trim();
            }
            const tag = p.tagName;
            if (/^H[1-3]$/.test(tag) && p.textContent.trim()) return p.textContent.trim();
            // Look for sibling/preceding heading
            let sib = p.previousElementSibling;
            while (sib) {
                if (/^H[1-3]$/.test(sib.tagName) && sib.textContent.trim()) {
                    return sib.textContent.trim();
                }
                sib = sib.previousElementSibling;
            }
            p = p.parentElement;
        }
        return '';
    }

    function getSelectOptions(el) {
        return Array.from(el.options).map(function (o) {
            return { value: o.value, text: o.text.trim() };
        });
    }

    // ── Extract ───────────────────────────────────────────────────────────────

    const EXCLUDE = new Set(['submit', 'button', 'reset', 'image', 'hidden']);
    const fields = [];
    const radioGroups = {};

    const inputs = document.querySelectorAll('input, select, textarea');

    inputs.forEach(function (el) {
        const type = (el.type || 'text').toLowerCase();
        if (EXCLUDE.has(type)) return;

        const id = el.id || '';
        const name = el.name || '';
        const label = resolveLabel(el);
        const section = resolveSection(el);

        if (type === 'radio') {
            const key = name || id || label;
            if (!radioGroups[key]) {
                radioGroups[key] = {
                    id: id,
                    name: name,
                    label: label,
                    type: 'radio',
                    section: section,
                    options: [],
                    value: ''
                };
            }
            const optLabel = resolveLabel(el);
            radioGroups[key].options.push({ value: el.value, text: optLabel });
            if (el.checked) radioGroups[key].value = el.value;
            return;
        }

        const field = {
            id: id,
            name: name,
            label: label,
            type: type === 'select-one' || type === 'select-multiple' ? 'select' : type,
            section: section,
            value: el.value || '',
            options: type.startsWith('select') ? getSelectOptions(el) : []
        };

        fields.push(field);
    });

    // Merge radio groups
    Object.values(radioGroups).forEach(function (g) { fields.push(g); });

    const result = JSON.stringify({ fields: fields, fieldCount: fields.length });

    // Post to Flutter
    if (window.AutofillChannel) {
        window.AutofillChannel.postMessage(result);
    } else {
        console.warn('[AutoFill] AutofillChannel not available');
    }
})();
