<script lang="ts">
  import { copyLink } from '../lib/hash-nav'

  interface Props {
    id: string
  }

  let { id }: Props = $props()
  let copied = $state(false)

  function handleClick() {
    copyLink(id)
    copied = true
    setTimeout(() => copied = false, 1500)
  }
</script>

<button
  onclick={handleClick}
  class="opacity-0 group-hover:opacity-100 transition-opacity text-gray-500 hover:text-gray-300 px-1"
  title="Copy link to #{id}"
>
  {#if copied}
    <span class="text-green-400">✓</span>
  {:else}
    <span class="text-sm">#</span>
  {/if}
</button>
