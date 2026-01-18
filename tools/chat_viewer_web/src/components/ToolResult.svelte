<script lang="ts">
  import type { RagResult, RagMatch } from '../lib/types'
  import { getMatchId } from '../lib/hash-nav'
  import CodeBlock from './CodeBlock.svelte'
  import LinkButton, { copy } from './LinkButton.svelte'
  import { getLanguageFromPath } from '../lib/highlight'

  interface Props {
    content: string
    msgIndex: number
  }

  let { content, msgIndex }: Props = $props()

  let showRawJson = $state(false)

  // Try to parse as JSON to check for RAG matches
  const parsed = $derived.by(() => {
    try {
      return JSON.parse(content)
    } catch {
      return null
    }
  })

  const isRagResult = $derived(
    parsed && typeof parsed === 'object' && Array.isArray(parsed.matches)
  )

  const ragMatches = $derived<RagMatch[]>(isRagResult ? parsed.matches : [])

  // Check if this is a tool result with message structure
  // e.g., { content: [{ type: "text", text: "..." }] }
  const isToolResultMessage = $derived(
    parsed &&
      typeof parsed === 'object' &&
      Array.isArray(parsed.content)
  )

  const extractedMessages = $derived.by(() => {
    if (!isToolResultMessage) return []
    return parsed.content
      .filter((item: any) => item.type === 'text')
      .map((item: any) => ({
        text: item.text || '',
        name: item.name,
      }))
  })
</script>

{#if isRagResult && ragMatches.length > 0}
  <div class="space-y-4">
    {#each ragMatches as match, idx}
      {@const matchId = getMatchId(msgIndex, idx + 1)}
      <div id={matchId} class="border border-gray-600 rounded scroll-mt-4">
        <div
          class="group px-3 py-1.5 bg-gray-700/50 text-sm font-mono text-red-400 border-b border-gray-600 flex justify-between items-center cursor-pointer"
          onclick={() => copy(matchId)}
        >
          <span>Match {idx + 1}: {match.file}</span>
          <div class="flex items-center gap-2">
            {#if match.rerank_score !== undefined}
              <span class="text-gray-500">score: {match.rerank_score.toFixed(3)}</span>
            {/if}
            <LinkButton id={matchId} />
          </div>
        </div>
        <div class="p-2">
          <CodeBlock code={match.text} language={getLanguageFromPath(match.file)} />
        </div>
      </div>
    {/each}
  </div>
{:else if isToolResultMessage}
  <!-- Tool result with message structure - show text by default, with toggle to JSON -->
  <div class="space-y-2">
    <div class="flex items-center gap-2 text-sm">
      <button
        class="px-2 py-1 rounded {showRawJson ? 'bg-gray-600 text-white' : 'bg-gray-800 text-gray-400'}"
        onclick={() => (showRawJson = true)}
      >
        Raw JSON
      </button>
      <button
        class="px-2 py-1 rounded {showRawJson ? 'bg-gray-800 text-gray-400' : 'bg-gray-600 text-white'}"
        onclick={() => (showRawJson = false)}
      >
        Show Message
      </button>
    </div>
    {#if showRawJson}
      <CodeBlock code={JSON.stringify(parsed, null, 2)} language="json" />
    {:else}
      <div class="space-y-3">
        {#each extractedMessages as msg}
          {#if msg.name}
            <div class="border border-gray-600 rounded">
              <div class="px-3 py-1.5 bg-gray-700/50 text-sm font-mono text-gray-400 border-b border-gray-600">
                {msg.name}
              </div>
              <div class="p-2 whitespace-pre-wrap text-gray-300 font-mono text-sm">
                {msg.text}
              </div>
            </div>
          {:else}
            <div class="whitespace-pre-wrap text-gray-300 font-mono text-sm">
              {msg.text}
            </div>
          {/if}
        {/each}
      </div>
    {/if}
  </div>
{:else if parsed}
  <!-- Generic JSON result -->
  <CodeBlock code={JSON.stringify(parsed, null, 2)} language="json" />
{:else}
  <!-- Plain text -->
  <div class="whitespace-pre-wrap text-gray-300 font-mono text-sm">
    {content}
  </div>
{/if}
