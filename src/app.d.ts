// See https://svelte.dev/docs/kit/types#app.d.ts
// for information about these interfaces
import type { AppUser } from '$lib/types';

declare global {
	namespace App {
		interface Locals {
			/** Angemeldeter User (Session-Cookie oder API-Token) oder null. */
			user: AppUser | null;
		}
	}
}
