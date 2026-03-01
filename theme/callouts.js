// =============================================================
// DeFi Protocol Engineering — Callout Box Detection
// =============================================================
// Transforms emoji-prefixed content into styled callout boxes.
// Runs after page load — no changes to markdown files needed.

(function() {
  'use strict';

  // Callout definitions: emoji → style
  var callouts = [
    { emoji: '\uD83D\uDCBB', cls: 'callout-try',     label: 'Quick Try',      color: '#3b82f6' }, // 💻
    { emoji: '\uD83C\uDFD7',  cls: 'callout-build',   label: 'Real Usage',     color: '#10b981' }, // 🏗️
    { emoji: '\uD83D\uDD0D', cls: 'callout-deep',    label: 'Deep Dive',      color: '#8b5cf6' }, // 🔍
    { emoji: '\uD83D\uDD17', cls: 'callout-pattern', label: 'DeFi Pattern',   color: '#f59e0b' }, // 🔗
    { emoji: '\uD83D\uDCBC', cls: 'callout-job',     label: 'Job Market',     color: '#ef4444' }, // 💼
    { emoji: '\uD83C\uDF93', cls: 'callout-example', label: 'Example',        color: '#06b6d4' }, // 🎓
    { emoji: '\uD83D\uDCCB', cls: 'callout-summary', label: 'Summary',        color: '#6366f1' }, // 📋
    { emoji: '\uD83D\uDCD6', cls: 'callout-study',   label: 'Study Guide',    color: '#14b8a6' }, // 📖
    { emoji: '\u26A0\uFE0F',  cls: 'callout-warning', label: 'Watch Out',      color: '#f97316' }, // ⚠️
    { emoji: '\uD83C\uDFAF', cls: 'callout-exercise',label: 'Exercise',       color: '#22c55e' }, // 🎯
  ];

  function injectStyles() {
    var css = '';

    // Base callout style
    css += '.callout{border-left:4px solid;border-radius:0 8px 8px 0;padding:1em 1.2em;margin:1.2em 0;position:relative;}';
    css += '.callout-label{font-weight:700;font-size:0.85rem;text-transform:uppercase;letter-spacing:0.05em;margin-bottom:0.5em;display:block;}';

    // Light theme
    callouts.forEach(function(c) {
      css += '.light .' + c.cls + '{border-left-color:' + c.color + ';background:' + c.color + '0a;}';
      css += '.light .' + c.cls + ' .callout-label{color:' + c.color + ';}';
    });

    // Dark themes
    ['navy', 'coal', 'ayu'].forEach(function(theme) {
      callouts.forEach(function(c) {
        css += '.' + theme + ' .' + c.cls + '{border-left-color:' + c.color + ';background:' + c.color + '12;}';
        css += '.' + theme + ' .' + c.cls + ' .callout-label{color:' + c.color + ';}';
      });
    });

    // Callout headings (h4 inside callouts)
    css += '.callout h4{margin-top:0 !important;padding-top:0;}';
    css += '.callout p:last-child{margin-bottom:0;}';

    var style = document.createElement('style');
    style.textContent = css;
    document.head.appendChild(style);
  }

  function wrapCallouts() {
    // Find h4 elements that start with callout emojis
    var headings = document.querySelectorAll('.content main h4');

    headings.forEach(function(h4) {
      var text = h4.textContent;

      callouts.forEach(function(c) {
        if (text.indexOf(c.emoji) === -1) return;

        // Collect all siblings until the next h2/h3/h4 or hr
        var elements = [h4];
        var next = h4.nextElementSibling;
        while (next && !next.matches('h1, h2, h3, h4, hr')) {
          elements.push(next);
          next = next.nextElementSibling;
        }

        // Create callout wrapper
        var wrapper = document.createElement('div');
        wrapper.className = 'callout ' + c.cls;

        // Insert before the h4
        h4.parentNode.insertBefore(wrapper, h4);

        // Move elements into wrapper
        elements.forEach(function(el) {
          wrapper.appendChild(el);
        });
      });
    });

    // Find paragraphs that start with callout emojis (inline callouts like "💻 **Quick Try:**")
    var paragraphs = document.querySelectorAll('.content main p');

    paragraphs.forEach(function(p) {
      var text = p.textContent;

      callouts.forEach(function(c) {
        // Check if paragraph starts with this emoji
        if (text.indexOf(c.emoji) !== 0) return;

        // Don't double-wrap if already in a callout
        if (p.closest('.callout')) return;

        // Collect this paragraph and following content until next heading/hr/emoji paragraph
        var elements = [p];
        var next = p.nextElementSibling;
        while (next) {
          // Stop at headings, hrs, or other callout paragraphs
          if (next.matches('h1, h2, h3, h4, hr')) break;
          if (next.matches('p') && callouts.some(function(cc) {
            return next.textContent.indexOf(cc.emoji) === 0;
          })) break;

          // Include code blocks and other content that follows
          elements.push(next);
          next = next.nextElementSibling;

          // Stop after first code block for Quick Try callouts
          if (c.cls === 'callout-try' && elements[elements.length - 1].matches('pre')) break;
        }

        var wrapper = document.createElement('div');
        wrapper.className = 'callout ' + c.cls;

        p.parentNode.insertBefore(wrapper, p);
        elements.forEach(function(el) {
          wrapper.appendChild(el);
        });
      });
    });
  }

  // Run on page load and on navigation (mdBook uses JS navigation)
  function init() {
    injectStyles();
    wrapCallouts();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  // Re-run on mdBook page navigation
  if (typeof window.addEventListener === 'function') {
    var observer = new MutationObserver(function(mutations) {
      mutations.forEach(function(m) {
        if (m.type === 'childList' && m.target.matches && m.target.matches('.content')) {
          wrapCallouts();
        }
      });
    });

    var content = document.querySelector('.content');
    if (content) {
      observer.observe(content, { childList: true, subtree: true });
    }
  }
})();
