<script lang="ts">
  import { parsePatch, groupChanges } from '../lib/patch-parser'
  import { getFileId } from '../lib/hash-nav'
  import CodeBlock from './CodeBlock.svelte'
  import LinkButton, { copy } from './LinkButton.svelte'

  interface Props {
    patch: string
    msgIndex?: number
    toolIndex?: number
  }

  let { patch, msgIndex = 0, toolIndex = 1 }: Props = $props()

  let showWordDiff = $state(true)

  const parsed = $derived(parsePatch(patch))

  function getActionColor(action: string): string {
    switch (action) {
      case 'add': return 'text-green-400'
      case 'delete': return 'text-red-400'
      case 'move': return 'text-purple-400'
      default: return 'text-blue-400'
    }
  }

  function getActionLabel(action: string): string {
    switch (action) {
      case 'add': return 'ADD'
      case 'delete': return 'DELETE'
      case 'move': return 'MOVE'
      default: return 'UPDATE'
    }
  }
</script>

<div class="space-y-4">
  <!-- Toggle -->
  <div class="flex items-center gap-2 text-sm">
    <button
      class="px-2 py-1 rounded {!showWordDiff ? 'bg-gray-600 text-white' : 'bg-gray-800 text-gray-400'}"
      onclick={() => showWordDiff = false}
    >
      Raw Diff
    </button>
    <button
      class="px-2 py-1 rounded {showWordDiff ? 'bg-gray-600 text-white' : 'bg-gray-800 text-gray-400'}"
      onclick={() => showWordDiff = true}
    >
      Word Diff
    </button>
  </div>

  {#if showWordDiff}
    <!-- Word diff view -->
    {#each parsed.files as file, idx}
      {@const fileId = getFileId(msgIndex, idx + 1)}
      <div id={fileId} class="border border-gray-600 rounded overflow-hidden scroll-mt-4">
        <div
          class="group px-3 py-1.5 bg-gray-700/50 text-sm font-mono border-b border-gray-600 flex gap-2 items-center justify-between cursor-pointer"
          onclick={() => copy(fileId)}
        >
          <div class="flex gap-2">
            <span class="{getActionColor(file.action)} font-bold">[{getActionLabel(file.action)}]</span>
            <span class="text-blue-400">{file.path}</span>
            {#if file.newPath}
              <span class="text-gray-500">→</span>
              <span class="text-purple-400">{file.newPath}</span>
            {/if}
          </div>
          <LinkButton id={fileId} />
        </div>
        <div class="p-2 bg-gray-900 font-mono text-sm overflow-x-auto">
          {#each file.hunks as hunk}
            {#if hunk.header}
              <div class="text-gray-500 mb-1">{hunk.header}</div>
            {/if}
            {@const groups = groupChanges(hunk.changes)}
            {#each groups as group}
              {#if group.type === 'context'}
                {#each group.context ?? [] as line}
                  <div class="text-gray-400 whitespace-pre">{line || '\u00A0'}</div>
                {/each}
              {:else if group.wordDiff}
                <div class="whitespace-pre-wrap">
                  {#each group.wordDiff as segment}
                    {#if segment.type === 'removed'}
                      <span class="bg-red-900/60 text-red-300">{segment.value}</span>
                    {:else if segment.type === 'added'}
                      <span class="bg-green-900/60 text-green-300">{segment.value}</span>
                    {:else}
                      <span class="text-gray-300">{segment.value}</span>
                    {/if}
                  {/each}
                </div>
              {/if}
            {/each}
          {/each}
        </div>
      </div>
    {/each}
  {:else}
    <!-- Raw diff view -->
    <CodeBlock code={patch} language="diff" />
  {/if}
</div>
