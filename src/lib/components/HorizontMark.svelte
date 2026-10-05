<script lang="ts">
	type Props = {
		size?: number;
		class?: string;
	} & Record<string, unknown>;

	let { size = 24, class: className = '', ...rest }: Props = $props();
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
	<path
		d="M104 316 Q256 268 408 316"
		fill="none"
		stroke="currentColor"
		stroke-width="18"
		stroke-linecap="round"
	/>
	<circle
		cx="256"
		cy="268"
		r="72"
		fill="none"
		stroke="currentColor"
		stroke-width="18"
	/>
</svg>
