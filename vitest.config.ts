// Vitest-Konfiguration für reine TS-Server-Module (keine .svelte-Tests,
// darum bewusst ohne das sveltekit()-Plugin). Aliase spiegeln svelte.config.js.
import { defineConfig } from 'vitest/config';

export default defineConfig({
	resolve: {
		alias: {
			$lib: new URL('./src/lib', import.meta.url).pathname,
			$server: new URL('./src/server', import.meta.url).pathname
		}
	},
	test: {
		environment: 'node',
		include: ['tests/**/*.test.ts']
	}
});
