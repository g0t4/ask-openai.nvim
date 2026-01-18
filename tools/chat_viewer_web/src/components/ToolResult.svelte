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
{:else if parsed}
  <!-- Generic JSON result -->
  <CodeBlock code={JSON.stringify(parsed, null, 2)} language="json" />
{:else}
  <!-- Plain text -->
  <div class="whitespace-pre-wrap text-gray-300 font-mono text-sm">
    {content}
  </div>
{/if}
