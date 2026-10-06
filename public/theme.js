const DEFAULT_THEME = 'amber';

const THEME_OPTIONS = [
  { id: 'amber', label: 'Amberkällare', group: 'Färg' },
  { id: 'slate', label: 'Skiffer', group: 'Färg' },
  { id: 'forest', label: 'Skog', group: 'Färg' },
  { id: 'falu', label: 'Faluröd', group: 'Färg' },
  { id: 'midsommar', label: 'Midsommar', group: 'Säsong' },
  { id: 'lucia', label: 'Lucia', group: 'Säsong' },
  { id: 'jul', label: 'Jul', group: 'Säsong' },
  { id: 'valborg', label: 'Valborg', group: 'Säsong' },
  { id: 'kraftskiva', label: 'Kräftskiva', group: 'Säsong' },
  { id: 'vinter', label: 'Vinter', group: 'Säsong' },
];

function isKnownTheme(themeId) {
  for (const theme of THEME_OPTIONS) {
    if (theme.id === themeId) {
      return true;
    }
  }
  return false;
}

function normalizeTheme(themeId) {
  if (isKnownTheme(themeId)) {
    return themeId;
  }
  return DEFAULT_THEME;
}

function applyTheme(themeId) {
  const theme = normalizeTheme(themeId);
  document.documentElement.setAttribute('data-theme', theme);
  return theme;
}

function fillThemeSelect(select, selectedId) {
  select.innerHTML = '';
  let currentGroup = null;
  let optgroup = null;

  for (const theme of THEME_OPTIONS) {
    if (theme.group !== currentGroup) {
      currentGroup = theme.group;
      optgroup = document.createElement('optgroup');
      optgroup.label = currentGroup;
      select.appendChild(optgroup);
    }

    const option = document.createElement('option');
    option.value = theme.id;
    option.textContent = theme.label;
    optgroup.appendChild(option);
  }

  select.value = normalizeTheme(selectedId);
}
