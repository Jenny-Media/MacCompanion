(() => {
  const modes = ['system', 'light', 'dark'];
  let mode = 'system';
  try { const saved = localStorage.getItem('maccompanion-appearance'); if (modes.includes(saved)) mode = saved; } catch {}
  const system = matchMedia('(prefers-color-scheme: dark)');
  let theme;
  function appearance() { return mode === 'system' ? (system.matches ? 'dark' : 'light') : mode; }
  function apply() {
    const current = appearance();
    document.documentElement.dataset.theme = current;
    if (theme) {
      const next = current === 'dark' ? 'light' : 'dark';
      const label = `Appearance: ${current}${mode === 'system' ? ' (system)' : ''}. Switch to ${next}`;
      theme.setAttribute('aria-label', label);
      theme.title = label;
    }
  }
  apply();
  system.addEventListener('change', apply);
  document.addEventListener('DOMContentLoaded', () => {
    theme = document.querySelector('.theme-toggle');
    apply();
    theme.addEventListener('click', () => { mode = appearance() === 'dark' ? 'light' : 'dark'; try { localStorage.setItem('maccompanion-appearance', mode); } catch {} apply(); });
    const menu = document.querySelector('.menu-toggle');
    const nav = document.querySelector('#site-nav');
    function close() { menu.setAttribute('aria-expanded', 'false'); menu.setAttribute('aria-label', 'Open navigation'); nav.classList.remove('open'); }
    menu.addEventListener('click', () => { const open = menu.getAttribute('aria-expanded') !== 'true'; menu.setAttribute('aria-expanded', String(open)); menu.setAttribute('aria-label', open ? 'Close navigation' : 'Open navigation'); nav.classList.toggle('open', open); });
    nav.addEventListener('click', e => { if (e.target.closest('a')) close(); });
    document.addEventListener('keydown', e => { if (e.key === 'Escape') { const wasOpen = menu.getAttribute('aria-expanded') === 'true'; close(); if (wasOpen) menu.focus({preventScroll: true}); } });
    document.addEventListener('click', e => { if (!e.target.closest('.site-header')) close(); });
    const current = location.pathname.replace(/\/$/, '') || '/';
    for (const link of nav.querySelectorAll('a')) if (!link.hash && link.pathname.replace(/\/$/, '') === current) link.setAttribute('aria-current', 'page');
  });
})();
