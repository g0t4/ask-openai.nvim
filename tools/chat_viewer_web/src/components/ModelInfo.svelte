<script lang="ts">
  interface Props {
    model?: string
  }

  let { model }: Props = $props()
</script>

{#if model}
  <div class="model-info mb-4 rounded-lg border border-gray-700 bg-gray-800/50">
    <div class="px-4 py-2 text-sm">
      <span class="text-gray-400">Model:</span>
      <span class="text-gray-200 font-medium ml-2">{model}</span>
    </div>
  </div>
{/if}
