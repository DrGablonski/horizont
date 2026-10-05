<script lang="ts" context="module">
	let uid = 0;
</script>

<script lang="ts">
	type Props = {
		size?: number;
		/** Behalten zum Rückwärtskompatibilitäts-Match; beide Varianten rendern denselben Sonnenaufgang. */
		variant?: 'reduced' | 'full';
		class?: string;
	} & Record<string, unknown>;

	let { size = 24, variant = 'reduced', class: className = '', ...rest }: Props = $props();
	const id = `hz-${++uid}`;
	void variant;
</script>

<svg
	viewBox="0 0 512 512"
	width={size}
	height={size}
	role="img"
	aria-label="Horizont"
	class={className}
	{...rest}
>
	<defs>
		<linearGradient id={`${id}-sky`} x1="0" y1="0" x2="0" y2="1">
			<stop offset="0" stop-color="#261854" />
			<stop offset="0.3" stop-color="#702866" />
			<stop offset="0.55" stop-color="#e05650" />
			<stop offset="0.8" stop-color="#ffa84e" />
			<stop offset="1" stop-color="#ffe08a" />
		</linearGradient>
		<clipPath id={`${id}-box`}>
			<rect width="512" height="512" rx="112" />
		</clipPath>
	</defs>
	<g clip-path={`url(#${id}-box)`}>
		<rect width="512" height="512" fill={`url(#${id}-sky)`} />
		<circle cx="256" cy="300" r="96" fill="#fff7ce" />
	</g>
</svg>
