<script lang="ts">
  import CodeBlock from './CodeBlock.svelte'
  import { getLanguageFromPath } from '../lib/highlight'

  interface Props {
    content: string
  }

  let { content }: Props = $props()

  interface Match {
    filePath: string
    startLine: string
    endLine: string
    snippet: string
  }

  const matches = $derived.by(() => {
    const lines = content.split('\n')
    const results: Match[] = []

    // Skip first line ("# Semantic Grep matches:")
    let idx = 1

    while (idx < lines.length) {
      const line = lines[idx]
      // Match pattern: ## /path/to/file:123-456
      const match = line.match(/^##\s+(.+?):(\d+)-(\d+)/)

      if (!match) {
        idx++
        continue
      }

      const filePath = match[1]
      const startLine = match[2]
      const endLine = match[3]

      // Collect snippet lines until next ## or end
      idx++
      const snippetLines: string[] = []
      while (idx < lines.length && !lines[idx].startsWith('## ')) {
        snippetLines.push(lines[idx])
        idx++
      }

      const snippet = snippetLines.join('\n')

      results.push({ filePath, startLine, endLine, snippet })
    }

    return results
  })
</script>

<div class="space-y-4">
  <div class="text-sm font-semibold text-gray-400 mb-4">
    Semantic Grep matches:
  </div>
  {#each matches as match}
    <div class="border border-gray-600 rounded">
      <div class="px-3 py-1.5 bg-gray-700/50 text-sm font-mono text-cyan-400 border-b border-gray-600">
        {match.filePath}:{match.startLine}-{match.endLine}
      </div>
      <div class="p-2">
        <CodeBlock code={match.snippet} language={getLanguageFromPath(match.filePath)} />
      </div>
    </div>
  {/each}
</div>
