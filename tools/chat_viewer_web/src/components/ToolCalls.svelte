<script lang="ts">
  import type { ToolCall } from '../lib/types'
  import CodeBlock from './CodeBlock.svelte'

  interface Props {
    calls: ToolCall[]
  }

  let { calls }: Props = $props()

  function formatArguments(name: string, argsJson: string): { code: string; language: string } {
    try {
      const parsed = JSON.parse(argsJson)

      // Special handling for apply_patch - show the diff
      if (name === 'apply_patch' && parsed.patch) {
        return { code: parsed.patch, language: 'diff' }
      }

      // Special handling for run_command - show the command
      if (name === 'run_command' && parsed.command) {
        return { code: parsed.command, language: 'bash' }
      }

      // Default: pretty print JSON
      return { code: JSON.stringify(parsed, null, 2), language: 'json' }
    } catch {
      return { code: argsJson, language: 'text' }
    }
  }
</script>

<div class="mt-4 space-y-3">
  {#each calls as call}
    {@const formatted = formatArguments(call.function.name, call.function.arguments)}
    <div class="border border-gray-600 rounded">
      <div class="px-3 py-1.5 bg-gray-700/50 text-sm font-mono text-yellow-400 border-b border-gray-600">
        {call.function.name}
      </div>
      <div class="p-2">
        <CodeBlock code={formatted.code} language={formatted.language} />
      </div>
    </div>
  {/each}
</div>
