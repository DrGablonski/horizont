<script lang="ts">
	type Props = {
		variant?: 'reduced' | 'full';
		class?: string;
	} & Record<string, unknown>;

	let { variant = 'reduced', class: className = '', ...rest }: Props = $props();
</script>

{#if variant === 'full'}
	<!-- Sonnenaufgang-Mark, 1024-Grid. Ab ~64px Höhe einsetzbar. -->
	<svg viewBox="166 413 692 172" fill="none" role="img" aria-label="Horizont" class={className} {...rest}>
		<path d="M174 545.5h676" stroke="currentColor" stroke-width="9" stroke-linecap="round" />
		<g stroke="currentColor" stroke-width="9" stroke-linecap="butt">
			<path d="M267.8 545.5v-19" />
			<path d="M319.8 545.5v-33" />
			<path d="M370.7 545.5v-43" />
			<path d="M653.3 545.5v-38" />
			<path d="M704.2 545.5v-51" />
			<path d="M756.2 545.5v-64" />
			<path d="M421.9 545.5a90.1 120.3 0 0 1 180.2 0" />
		</g>
		<circle cx="512" cy="545.5" r="31" fill="currentColor" />
	</svg>
{:else}
	<!-- Reduziertes Mark für 16–32px: keine Ticks, dickere Linien. -->
	<svg viewBox="0 7 32 15" fill="none" role="img" aria-label="Horizont" class={className} {...rest}>
		<path d="M3 17h26" stroke="currentColor" stroke-width="3" stroke-linecap="round" />
		<path d="M10.8 17a5.2 7 0 0 1 10.4 0" stroke="currentColor" stroke-width="3" stroke-linecap="butt" />
		<circle cx="16" cy="17" r="3.6" fill="currentColor" />
	</svg>
{/if}
