(function (mappingsJson) {
    'use strict';

    var mappings;
    try {
        mappings = JSON.parse(mappingsJson);
    } catch (e) {
        console.error('[FormFiller] Bad JSON:', e);
        return;
    }

    // ── Native setter to bypass React's synthetic events ────────────────────

    function nativeSet(el, value) {
        try {
            var nativeSetter = Object.getOwnPropertyDescriptor(
                el.tagName === 'SELECT'
                    ? HTMLSelectElement.prototype
                    : el.tagName === 'TEXTAREA'
                        ? HTMLTextAreaElement.prototype
                        : HTMLInputElement.prototype,
                'value'
            );
            if (nativeSetter && nativeSetter.set) {
                nativeSetter.set.call(el, value);
                return true;
            }
        } catch (e) { }
        try {
            el.value = value;
            return true;
        } catch (e2) { }
        return false;
    }

    // ── Dispatch events for different frameworks ─────────────────────────────

    function dispatchEvents(el) {
        ['focus', 'input', 'change', 'blur'].forEach(function (evtName) {
            var evt;
            try {
                evt = new Event(evtName, { bubbles: true, cancelable: true });
            } catch (e) {
                evt = document.createEvent('Event');
                evt.initEvent(evtName, true, true);
            }
            el.dispatchEvent(evt);
        });
    }

    // ── Lookup element ────────────────────────────────────────────────────────

    function findElement(id, name) {
        if (id) {
            var byId = document.getElementById(id);
            if (byId) return byId;
            var byName = document.querySelector('[name="' + id + '"]');
            if (byName) return byName;
        }
        if (name) {
            var n1 = document.querySelector('[name="' + name + '"]');
            if (n1) return n1;
            var n2 = document.querySelector('[name*="' + name + '"]');
            if (n2) return n2;
        }
        return null;
    }

    // ── Fill a <select> with closest-match ───────────────────────────────────

    function fillSelect(el, value) {
        var lv = value.toString().toLowerCase().trim();
        // Pass 1: exact value/text match
        for (var i = 0; i < el.options.length; i++) {
            var opt = el.options[i];
            if (opt.value.toLowerCase() === lv || opt.text.toLowerCase() === lv) {
                nativeSet(el, opt.value);
                dispatchEvents(el);
                return true;
            }
        }
        // Pass 2: containment match
        for (var j = 0; j < el.options.length; j++) {
            var o = el.options[j];
            if (o.value.toLowerCase().includes(lv) || o.text.toLowerCase().includes(lv) ||
                lv.includes(o.value.toLowerCase()) || lv.includes(o.text.toLowerCase())) {
                nativeSet(el, o.value);
                dispatchEvents(el);
                return true;
            }
        }
        return false;
    }

    // ── Main fill loop ────────────────────────────────────────────────────────

    var filled = 0;
    var skipped = 0;
    var results = [];

    mappings.forEach(function (entry) {
        var fieldId = entry.id || '';
        var fieldName = entry.name || '';
        var value = entry.value;
        if (value === null || value === undefined) { skipped++; results.push({ id: fieldId, status: 'skipped' }); return; }

        var el = findElement(fieldId, fieldName);
        if (!el) { skipped++; results.push({ id: fieldId, status: 'not_found' }); return; }

        var tag = el.tagName.toLowerCase();
        var type = (el.type || '').toLowerCase();

        if (tag === 'select') {
            if (fillSelect(el, value)) { filled++; results.push({ id: fieldId, status: 'filled' }); }
            else { skipped++; results.push({ id: fieldId, status: 'no_match' }); }
        } else if (type === 'checkbox') {
            el.checked = (value === true || value === 'true' || value === '1' || value === 'on');
            dispatchEvents(el);
            filled++;
            results.push({ id: fieldId, status: 'filled' });
        } else if (type === 'radio') {
            var radios = document.querySelectorAll('[name="' + (fieldName || fieldId) + '"]');
            var matched = false;
            radios.forEach(function (r) {
                if (r.value.toLowerCase() === value.toString().toLowerCase()) {
                    r.checked = true;
                    dispatchEvents(r);
                    matched = true;
                }
            });
            if (matched) { filled++; results.push({ id: fieldId, status: 'filled' }); }
            else { skipped++; results.push({ id: fieldId, status: 'no_match' }); }
        } else {
            nativeSet(el, value.toString());
            dispatchEvents(el);
            filled++;
            results.push({ id: fieldId, status: 'filled' });
        }
    });

    // Report back
    if (window.AutofillChannel) {
        window.AutofillChannel.postMessage(JSON.stringify({
            event: 'fill_complete',
            filled: filled,
            skipped: skipped,
            results: results
        }));
    }
})(MAPPINGS_PLACEHOLDER);
