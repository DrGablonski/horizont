// Theme (hell / dunkel). Wird client-seitig angewendet: Klasse „dark" auf
// <html>. Kein SSR — bewusst ohne Reactivity-Runen, da dies ein .ts-Modul ist.

export type Theme = 'light' | 'dark' | 'system';

const STORAGE_KEY = 'horizont-theme';

export function systemPrefersDark(): boolean {
	return (
		typeof window !== 'undefined' &&
		window.matchMedia('(prefers-color-scheme: dark)').matches
	);
}

export function isDarkFor(theme: Theme): boolean {
	return theme === 'dark' || (theme === 'system' && systemPrefersDark());
}

export function getStoredTheme(): Theme {
	if (typeof localStorage === 'undefined') return 'system';
	const s = localStorage.getItem(STORAGE_KEY);
	if (s === 'light' || s === 'dark' || s === 'system') return s;
	return 'system';
}

/** Wendet das Theme auf <html> an (Client). */
export function applyTheme(theme: Theme): void {
	if (typeof document === 'undefined') return;
	document.documentElement.classList.toggle('dark', isDarkFor(theme));
}

/** Speichert und wendet ein explizites Theme an. */
export function setTheme(theme: Exclude<Theme, 'system'>): Exclude<Theme, 'system'> {
	if (typeof localStorage !== 'undefined') localStorage.setItem(STORAGE_KEY, theme);
	applyTheme(theme);
	return theme;
}

/** Toggling zwischen hell/dunkel; gibt das neue explizite Theme zurück. */
export function toggleTheme(): Exclude<Theme, 'system'> {
	const cur = getStoredTheme();
	const next = isDarkFor(cur) ? 'light' : 'dark';
	return setTheme(next);
}
