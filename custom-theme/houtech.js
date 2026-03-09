/* ============================================================
   HOUTECH PI-HOLE REBRANDING SCRIPT
   Replaces all Pi-hole text/links with HouTech branding
   Works on all pages including login
   ============================================================ */

(function() {

  // ── TEXT REPLACEMENTS ──────────────────────────────────────
  const replacements = [
    [/Pi-hole/g,               'HouTech'],
    [/Pi hole/g,               'HouTech'],
    [/Pihole/g,                'HouTech'],
    [/pihole/g,                'houtech'],
    [/PIHOLE/g,                'HOUTECH'],
    [/The Pi-hole project/gi,  'HouTech'],
    [/pi-hole\.net/gi,         'houtech.org'],
    [/discourse\.pi-hole\.net/gi, 'houtech.org'],
    [/docs\.pi-hole\.net/gi,   'houtech.org'],
  ];

  // ── LINK REPLACEMENTS ─────────────────────────────────────
  const linkReplacements = [
    [/https?:\/\/pi-hole\.net.*/gi,           'https://houtech.org'],
    [/https?:\/\/discourse\.pi-hole\.net.*/gi,'https://houtech.org'],
    [/https?:\/\/docs\.pi-hole\.net.*/gi,     'https://houtech.org'],
    [/https?:\/\/github\.com\/pi-hole.*/gi,   'https://houtech.org'],
  ];

  // ── ATTRIBUTE REPLACEMENTS (placeholder, title, alt, etc) ─
  const attrReplacements = [
    ['placeholder'], ['title'], ['alt'], ['aria-label'], ['value']
  ];

  function rebrandNode(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      let val = node.nodeValue;
      let changed = false;
      for (const [pattern, replacement] of replacements) {
        if (pattern.test(val)) {
          val = val.replace(pattern, replacement);
          changed = true;
        }
        // Reset lastIndex for global regexes
        pattern.lastIndex = 0;
      }
      if (changed) node.nodeValue = val;

    } else if (node.nodeType === Node.ELEMENT_NODE) {
      if (node.tagName === 'SCRIPT' || node.tagName === 'STYLE') return;

      // Rebrand attributes
      for (const [attr] of attrReplacements) {
        if (node.hasAttribute(attr)) {
          let val = node.getAttribute(attr);
          let changed = false;
          for (const [pattern, replacement] of replacements) {
            if (pattern.test(val)) {
              val = val.replace(pattern, replacement);
              changed = true;
            }
            pattern.lastIndex = 0;
          }
          if (changed) node.setAttribute(attr, val);
        }
      }

      // Recurse children
      for (const child of node.childNodes) {
        rebrandNode(child);
      }
    }
  }

  function rebrandLinks() {
    document.querySelectorAll('a[href]').forEach(a => {
      for (const [pattern, replacement] of linkReplacements) {
        if (pattern.test(a.href)) {
          a.href = replacement;
          a.target = '_blank';
          a.rel = 'noopener';
        }
        pattern.lastIndex = 0;
      }
    });
  }

  function rebrandTitle() {
    if (document.title) {
      let t = document.title;
      for (const [pattern, replacement] of replacements) {
        t = t.replace(pattern, replacement);
        pattern.lastIndex = 0;
      }
      document.title = t;
    }
  }

  // ── LOGIN PAGE SPECIFIC ────────────────────────────────────
  function rebrandLoginPage() {
    // Replace login heading text
    const headings = document.querySelectorAll('h1, h2, h3, h4, .login-box-msg, .panel-title, title');
    headings.forEach(el => {
      if (el.innerHTML) {
        el.innerHTML = el.innerHTML
          .replace(/Pi-hole/gi, 'HouTech')
          .replace(/Pi hole/gi, 'HouTech')
          .replace(/pihole/gi, 'houtech');
      }
    });

    // Replace any logo img alt text
    document.querySelectorAll('img').forEach(img => {
      if (img.alt) {
        img.alt = img.alt
          .replace(/Pi-hole/gi, 'HouTech')
          .replace(/Pi hole/gi, 'HouTech');
      }
    });

    // Replace password input placeholder
    document.querySelectorAll('input[type="password"]').forEach(el => {
      el.placeholder = 'HouTech Password';
    });
  }

  function runAll() {
    rebrandNode(document.body);
    rebrandLinks();
    rebrandTitle();
    rebrandLoginPage();
  }

  // Run immediately and on DOMContentLoaded
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', runAll);
  } else {
    runAll();
  }

  // Watch for async content updates
  const observer = new MutationObserver(function(mutations) {
    for (const mutation of mutations) {
      for (const node of mutation.addedNodes) {
        rebrandNode(node);
      }
    }
    rebrandLinks();
    rebrandTitle();
  });

  if (document.body) {
    observer.observe(document.body, { childList: true, subtree: true });
  }

})();
