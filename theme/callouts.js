// =============================================================
// DeFi Protocol Engineering — Callout Box Detection
// =============================================================
// Transforms emoji-prefixed content into styled callout boxes.
// Also: H2 section color coding, code block language labels.
// Runs after page load — no changes to markdown files needed.
// Styles are defined in custom.css — this file only handles detection + wrapping.

(function() {
  'use strict';

  // Callout definitions: emoji → CSS class + label text + icon
  // NOTE: 🎯 is NOT here — it's only used for H2 section coloring, not callout wrapping
  var callouts = [
    { emoji: '\uD83D\uDCBB', cls: 'callout-try',      label: 'Quick Try',      icon: '\uD83D\uDCBB' }, // 💻
    { emoji: '\uD83C\uDFD7',  cls: 'callout-build',    label: 'Real Usage',     icon: '\uD83C\uDFD7\uFE0F' },  // 🏗️
    { emoji: '\uD83D\uDD0D', cls: 'callout-deep',     label: 'Deep Dive',      icon: '\uD83D\uDD0D' }, // 🔍
    { emoji: '\uD83D\uDD17', cls: 'callout-pattern',  label: 'DeFi Pattern',   icon: '\uD83D\uDD17' }, // 🔗
    { emoji: '\uD83D\uDCBC', cls: 'callout-job',      label: 'Job Market',     icon: '\uD83D\uDCBC' }, // 💼
    { emoji: '\uD83C\uDF93', cls: 'callout-example',  label: 'Example',        icon: '\uD83C\uDF93' }, // 🎓
    { emoji: '\uD83D\uDCCB', cls: 'callout-summary',  label: 'Summary',        icon: '\uD83D\uDCCB' }, // 📋
    { emoji: '\uD83D\uDCD6', cls: 'callout-study',    label: 'Study Guide',    icon: '\uD83D\uDCD6' }, // 📖
    { emoji: '\u26A0\uFE0F',  cls: 'callout-warning',  label: 'Watch Out',      icon: '\u26A0\uFE0F' },  // ⚠️
  ];

  // H2 section types: emoji → CSS class for colored border
  var sectionTypes = [
    { emoji: '\uD83D\uDCA1', cls: 'section-concept'  }, // 💡 Why/Concept
    { emoji: '\uD83C\uDFAF', cls: 'section-exercise' }, // 🎯 Exercise/Practice
    { emoji: '\uD83D\uDCCB', cls: 'section-summary'  }, // 📋 Summary/Takeaways
    { emoji: '\uD83D\uDCDA', cls: 'section-resources' }, // 📚 TOC/Resources
    { emoji: '\uD83D\uDD17', cls: 'section-links'    }, // 🔗 Cross-Module/Patterns
    { emoji: '\uD83D\uDCBC', cls: 'section-job'      }, // 💼 Job Market
    { emoji: '\u26A0\uFE0F',  cls: 'section-warning'  }, // ⚠️ Common Mistakes
    { emoji: '\uD83D\uDCD6', cls: 'section-study'    }, // 📖 Study Guide
    { emoji: '\uD83D\uDEE0', cls: 'section-build'    }, // 🛠️ Build Order
    { emoji: '\u2705',       cls: 'section-check'    }, // ✅ Self-Assessment
    { emoji: '\uD83C\uDF89', cls: 'section-complete'  }, // 🎉 Part Complete
  ];

  // Language display names for code block labels
  var langNames = {
    'solidity': 'Solidity',
    'sol': 'Solidity',
    'javascript': 'JavaScript',
    'js': 'JavaScript',
    'typescript': 'TypeScript',
    'ts': 'TypeScript',
    'rust': 'Rust',
    'python': 'Python',
    'py': 'Python',
    'bash': 'Bash',
    'shell': 'Shell',
    'sh': 'Shell',
    'toml': 'TOML',
    'json': 'JSON',
    'yaml': 'YAML',
    'yml': 'YAML',
    'markdown': 'Markdown',
    'md': 'Markdown',
  };

  // Elements that should stop callout content collection
  function isStopElement(el) {
    if (!el) return true;
    if (el.matches('h1, h2, h3, h4, hr')) return true;
    // Another callout-starting paragraph
    if (el.matches('p') && callouts.some(function(c) {
      return el.textContent.indexOf(c.emoji) === 0;
    })) return true;
    return false;
  }

  function createLabel(callout) {
    var label = document.createElement('div');
    label.className = 'callout-label';
    label.textContent = callout.icon + ' ' + callout.label;
    return label;
  }

  // Strip the emoji and label text from the triggering element
  // e.g. "💻 Quick Try:" → remaining text after the label
  function stripEmojiPrefix(el, callout) {
    // Walk text nodes to find and remove the emoji prefix
    var walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT, null, false);
    var node;
    while (node = walker.nextNode()) {
      var idx = node.textContent.indexOf(callout.emoji);
      if (idx !== -1) {
        // Remove everything up to and including the emoji + any following whitespace/colon/bold markers
        var after = node.textContent.substring(idx + callout.emoji.length);
        // Also strip variation selectors (️) that follow some emojis
        after = after.replace(/^\uFE0F/, '');
        node.textContent = after;
        break;
      }
    }
  }

  // --- H2 Section Color Coding ---
  function colorSections() {
    var main = document.querySelector('.content main');
    if (!main) return;

    var headings = main.querySelectorAll('h2');
    headings.forEach(function(h2) {
      if (h2.dataset.sectionColored) return;
      var text = h2.textContent;

      sectionTypes.forEach(function(s) {
        if (text.indexOf(s.emoji) !== -1) {
          h2.classList.add(s.cls);
          h2.dataset.sectionColored = 'true';
        }
      });
    });
  }

  // --- Code Block Language Labels ---
  function labelCodeBlocks() {
    var main = document.querySelector('.content main');
    if (!main) return;

    var blocks = main.querySelectorAll('pre > code[class*="language-"]');
    blocks.forEach(function(code) {
      var pre = code.parentElement;
      if (pre.dataset.langLabeled) return;

      // Extract language from class
      var match = code.className.match(/language-(\w+)/);
      if (!match) return;

      var lang = match[1].toLowerCase();
      var displayName = langNames[lang];
      if (!displayName) return;

      // Create label
      var label = document.createElement('span');
      label.className = 'code-lang-label';
      label.textContent = displayName;
      pre.style.position = 'relative';
      pre.insertBefore(label, pre.firstChild);
      pre.dataset.langLabeled = 'true';
    });
  }

  // --- Callout Wrapping ---
  function wrapCallouts() {
    var main = document.querySelector('.content main');
    if (!main) return;

    // --- Pass 1: h4 headings that contain callout emojis ---
    var headings = main.querySelectorAll('h4');

    headings.forEach(function(h4) {
      if (h4.closest('.callout')) return;

      var text = h4.textContent;

      callouts.forEach(function(c) {
        if (text.indexOf(c.emoji) === -1) return;
        if (h4.closest('.callout')) return;

        var elements = [];
        var next = h4.nextElementSibling;
        while (next && !isStopElement(next)) {
          elements.push(next);
          next = next.nextElementSibling;
        }

        var wrapper = document.createElement('div');
        wrapper.className = 'callout ' + c.cls;
        wrapper.appendChild(createLabel(c));
        h4.parentNode.insertBefore(wrapper, h4);
        h4.style.display = 'none';
        wrapper.appendChild(h4);

        elements.forEach(function(el) {
          wrapper.appendChild(el);
        });
      });
    });

    // --- Pass 2: paragraphs that start with callout emojis ---
    var paragraphs = main.querySelectorAll('p');

    paragraphs.forEach(function(p) {
      if (p.closest('.callout')) return;

      var text = p.textContent;

      callouts.forEach(function(c) {
        if (text.indexOf(c.emoji) !== 0) return;
        if (p.closest('.callout')) return;

        var elements = [];
        var next = p.nextElementSibling;
        while (next && !isStopElement(next)) {
          elements.push(next);
          next = next.nextElementSibling;

          if (c.cls === 'callout-try' && elements.length > 0 &&
              elements[elements.length - 1].matches('pre')) {
            break;
          }
        }

        var wrapper = document.createElement('div');
        wrapper.className = 'callout ' + c.cls;
        wrapper.appendChild(createLabel(c));

        p.parentNode.insertBefore(wrapper, p);

        // Hide the triggering paragraph — the label already shows it
        p.style.display = 'none';
        wrapper.appendChild(p);

        elements.forEach(function(el) {
          wrapper.appendChild(el);
        });
      });
    });
  }

  // --- Initialize ---
  function init() {
    colorSections();
    labelCodeBlocks();
    wrapCallouts();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  // Re-run on mdBook client-side navigation
  var content = document.querySelector('.content');
  if (content) {
    var observer = new MutationObserver(function(mutations) {
      var dominated = mutations.some(function(m) {
        return m.type === 'childList' && m.addedNodes.length > 0;
      });
      if (dominated) {
        setTimeout(init, 50);
      }
    });
    observer.observe(content, { childList: true, subtree: false });
  }
})();
