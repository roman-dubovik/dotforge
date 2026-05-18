/* dotforge landing — scripts.js */

/* ── Copy-to-clipboard ─────────────────────────────────────────────── */
function copyTextToClipboard(btn, text) {
    var icon = btn.querySelector('.copy-icon');
    var label = btn.querySelector('.copy-label');
    var original = label ? label.textContent : '';

    function showCopied() {
        btn.classList.add('copied');
        if (icon) icon.textContent = '✓';
        if (label) label.textContent = 'Copied';
        setTimeout(function() {
            btn.classList.remove('copied');
            if (icon) icon.textContent = '⧉';
            if (label) label.textContent = original;
        }, 2000);
    }

    function showFailed(err) {
        if (err) console.error('dotforge: clipboard copy failed', err);
        if (label) {
            label.textContent = 'Copy failed';
            setTimeout(function() { if (label) label.textContent = original; }, 2000);
        }
    }

    function fallback() {
        try {
            var ta = document.createElement('textarea');
            ta.value = text;
            ta.setAttribute('readonly', '');
            ta.style.position = 'absolute';
            ta.style.left = '-9999px';
            document.body.appendChild(ta);
            ta.select();
            var ok = document.execCommand('copy');
            document.body.removeChild(ta);
            if (ok) showCopied(); else showFailed(null);
        } catch (e) {
            showFailed(e);
        }
    }

    if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
        navigator.clipboard.writeText(text).then(showCopied).catch(function(e) {
            console.warn('dotforge: clipboard API failed, falling back', e);
            fallback();
        });
    } else {
        fallback();
    }
}

document.querySelectorAll('.copy-btn').forEach(function(btn) {
  btn.addEventListener('click', function() {
    var row = btn.closest('.code-row');
    var codeEl = row ? row.querySelector('code') : null;
    if (!codeEl) return;
    copyTextToClipboard(btn, codeEl.textContent.trim());
  });
});

/* ── Smooth scroll for in-page nav links ──────────────────────────── */
document.querySelectorAll('a[href^="#"]').forEach(function(link) {
  link.addEventListener('click', function(e) {
    var id = link.getAttribute('href').slice(1);
    var target = document.getElementById(id);
    if (!target) return;
    e.preventDefault();
    var headerHeight = (document.querySelector('.site-header') || {}).offsetHeight || 60;
    var top = target.getBoundingClientRect().top + window.scrollY - headerHeight - 12;
    window.scrollTo({ top: top, behavior: 'smooth' });
  });
});

/* ── Scroll-reveal ─────────────────────────────────────────────────── */
(function() {
  if (!window.IntersectionObserver) return;
  var observer = new IntersectionObserver(function(entries) {
    entries.forEach(function(entry) {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });

  document.querySelectorAll('.reveal').forEach(function(el) {
    observer.observe(el);
  });
})();

/* ── Active nav highlight on scroll ──────────────────────────────── */
(function() {
  var sections = document.querySelectorAll('section[id]');
  var navLinks = document.querySelectorAll('.site-nav a[href^="#"]');
  if (!sections.length || !navLinks.length) return;

  function onScroll() {
    var scrollY = window.scrollY + 80;
    var current = '';
    sections.forEach(function(s) {
      if (s.offsetTop <= scrollY) current = s.id;
    });
    navLinks.forEach(function(a) {
      a.style.color = '';
      if (a.getAttribute('href') === '#' + current) {
        a.style.color = 'var(--amber)';
      }
    });
  }
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();
})();
