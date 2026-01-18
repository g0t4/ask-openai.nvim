<script lang="ts" module>
  import { copyLink } from '../lib/hash-nav'

  // Shared state for copied feedback across all instances
  let copiedId = $state<string | null>(null)

  export function copy(id: string) {
    copyLink(id)
    copiedId = id
    setTimeout(() => copiedId = null, 1500)
  }
</script>

<script lang="ts">
  interface Props {
    id: string
  }

  let { id }: Props = $props()

  const isCopied = $derived(copiedId === id)
</script>

<span
  class="opacity-0 group-hover:opacity-100 transition-opacity text-gray-500 px-1 select-none"
>
  {#if isCopied}
    <span class="text-green-400">✓</span>
  {:else}
    <span class="text-sm">#</span>
  {/if}
</span>
