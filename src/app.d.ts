// See https://svelte.dev/docs/kit/types#app.d.ts
// for information about these interfaces
declare global {
	namespace App {
		interface Locals {
			/** Angemeldeter User (aus Session-Cookie) oder null. */
			user: {
				id: string;
				username: string;
				role: 'admin' | 'user';
				createdAt: number;
				lastLoginAt: number | null;
			} | null;
		}
	}
}

export {};
