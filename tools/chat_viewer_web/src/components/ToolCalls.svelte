<script lang="ts">
  import type { ToolCall } from '../lib/types'
  import { getToolCallId } from '../lib/hash-nav'
  import CodeBlock from './CodeBlock.svelte'
  import ApplyPatch from './ApplyPatch.svelte'
  import LinkButton, { copy } from './LinkButton.svelte'

  interface Props {
    calls: ToolCall[]
    msgIndex: number
  }

  let { calls, msgIndex }: Props = $props()

  interface FormattedArgs {
    type: 'code' | 'patch'
    code?: string
    language?: string
    patch?: string
  }

  function formatArguments(name: string, argsJson: string): FormattedArgs {
    try {
      const parsed = JSON.parse(argsJson)

      // Special handling for apply_patch - use dedicated component
      if (name === 'apply_patch' && parsed.patch) {
        return { type: 'patch', patch: parsed.patch }
      }

      // Special handling for run_command - show the command
      if (name === 'run_command' && parsed.command) {
        return { type: 'code', code: parsed.command, language: 'bash' }
      }

      // Default: pretty print JSON
      return { type: 'code', code: JSON.stringify(parsed, null, 2), language: 'json' }
    } catch {
      return { type: 'code', code: argsJson, language: 'text' }
    }
  }
</script>

<div class="mt-4 space-y-3">
  {#each calls as call, idx}
    {@const formatted = formatArguments(call.function.name, call.function.arguments)}
    {@const toolId = getToolCallId(msgIndex, idx + 1)}
    <div id={toolId} class="border border-gray-600 rounded scroll-mt-4">
      <div
        class="group px-3 py-1.5 bg-gray-700/50 text-sm font-mono text-yellow-400 border-b border-gray-600 flex items-center justify-between cursor-pointer"
        onclick={() => copy(toolId)}
      >
        <span>{call.function.name}</span>
        <LinkButton id={toolId} />
      </div>
      <div class="p-2">
        {#if formatted.type === 'patch' && formatted.patch}
          <ApplyPatch patch={formatted.patch} {msgIndex} toolIndex={idx + 1} />
        {:else if formatted.code}
          <CodeBlock code={formatted.code} language={formatted.language ?? 'text'} />
        {/if}
      </div>
    </div>
  {/each}
</div>
