/* Love Vibe Admin Panel — JS */

'use strict';

/* ---- Table search ---- */
function bindTableSearch(inputId, tableId) {
  const inp = document.getElementById(inputId);
  const tbl = document.getElementById(tableId);
  if (!inp || !tbl) return;
  inp.addEventListener('input', () => {
    const q = inp.value.toLowerCase().trim();
    tbl.querySelectorAll('tbody tr').forEach(row => {
      row.style.display = row.textContent.toLowerCase().includes(q) ? '' : 'none';
    });
  });
}

/* ---- Confirm delete shortcut ---- */
function confirmDelete(msg) {
  return confirm(msg || 'Are you sure you want to delete this?');
}

/* ---- Mobile sidebar toggle ---- */
function initSidebar() {
  const toggle  = document.querySelector('.menu-toggle');
  const sidebar = document.querySelector('.sidebar');
  const overlay = document.querySelector('.sidebar-overlay');
  if (!toggle || !sidebar) return;

  toggle.addEventListener('click', () => {
    sidebar.classList.toggle('open');
    overlay && overlay.classList.toggle('show');
  });
  overlay && overlay.addEventListener('click', () => {
    sidebar.classList.remove('open');
    overlay.classList.remove('show');
  });
}

/* ---- Auto-hide alerts ---- */
function autoHideAlerts() {
  document.querySelectorAll('.badge.ok, .alert.ok').forEach(el => {
    setTimeout(() => {
      el.style.transition = 'opacity .5s';
      el.style.opacity = '0';
      setTimeout(() => el.remove(), 500);
    }, 4000);
  });
}

/* ---- Confirm form submissions ---- */
function bindConfirmForms() {
  document.querySelectorAll('[data-confirm]').forEach(el => {
    el.addEventListener('click', e => {
      if (!confirm(el.dataset.confirm)) e.preventDefault();
    });
  });
}

/* ---- Select-all checkbox ---- */
function initSelectAll() {
  const master = document.querySelector('.select-all');
  if (!master) return;
  master.addEventListener('change', () => {
    document.querySelectorAll('.select-row').forEach(cb => { cb.checked = master.checked; });
  });
}

/* ---- Number formatter in stat boxes ---- */
function animateCounters() {
  document.querySelectorAll('.val[data-target]').forEach(el => {
    const target = +el.dataset.target;
    let cur = 0;
    const step = Math.ceil(target / 60);
    const tick = setInterval(() => {
      cur = Math.min(cur + step, target);
      el.textContent = cur.toLocaleString();
      if (cur >= target) clearInterval(tick);
    }, 16);
  });
}

/* ---- Toast notification ---- */
function showToast(msg, type = 'ok') {
  const t = document.createElement('div');
  t.className = `badge ${type}`;
  t.style.cssText = 'position:fixed;bottom:24px;right:24px;z-index:9999;padding:12px 20px;font-size:13px;box-shadow:0 8px 24px rgba(0,0,0,.4);border-radius:10px;animation:fadeIn .3s';
  t.textContent = msg;
  document.body.appendChild(t);
  setTimeout(() => { t.style.opacity = '0'; t.style.transition = 'opacity .4s'; setTimeout(() => t.remove(), 400); }, 3000);
}

/* ---- Image preview on URL input ---- */
function bindImagePreviews() {
  document.querySelectorAll('input[data-preview]').forEach(inp => {
    const target = document.getElementById(inp.dataset.preview);
    if (!target) return;
    inp.addEventListener('input', () => {
      target.src = inp.value || '';
      target.style.display = inp.value ? 'block' : 'none';
    });
  });
}

/* ---- Dropdown with search in forms ---- */
function enhanceSelects() {
  /* placeholder for future enhancement */
}

/* ---- Init ---- */
document.addEventListener('DOMContentLoaded', () => {
  initSidebar();
  autoHideAlerts();
  bindConfirmForms();
  initSelectAll();
  bindImagePreviews();
  enhanceSelects();
});

/* ---- CSS animation inject ---- */
const style = document.createElement('style');
style.textContent = `
@keyframes fadeIn { from { opacity:0; transform:translateY(8px); } to { opacity:1; transform:translateY(0); } }
@keyframes slideIn { from { transform:translateX(-100%); } to { transform:translateX(0); } }
`;
document.head.appendChild(style);
