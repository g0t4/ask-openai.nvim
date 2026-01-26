<script lang="ts">
  import { getTimestampInfo } from '../lib/timestamp-utils'

  interface LocalItem {
    name: string
    path: string
    type: 'file' | 'dir'
  }

  interface Props {
    localPath: string // e.g., "semantic_grep_auto_context/fims"
  }

  let { localPath }: Props = $props()

  let items: LocalItem[] = $state([])
  let loading = $state(true)
  let error = $state<string | null>(null)

  // Build app URL for navigation
  function buildAppUrl(itemPath: string, isDir: boolean): string {
    // Add trailing slash for directories
    const pathWithSlash = isDir && !itemPath.endsWith('/') ? itemPath + '/' : itemPath
    // Don't encode slashes - keep URLs readable
    return `${window.location.pathname}?local=${pathWithSlash}${window.location.hash}`
  }

  // Get parent directory path
  const parentPath = $derived.by(() => {
    if (!localPath) return null
    const parts = localPath.split('/').filter(Boolean)
    if (parts.length === 0) return null
    parts.pop()
    return parts.join('/')
  })

  async function loadDirectory() {
    loading = true
    error = null
    items = []

    try {
      // Call local directory listing API
      const apiUrl = `/api/local/list?path=${encodeURIComponent(localPath)}`

      const response = await fetch(apiUrl)

      if (!response.ok) {
        const errorData = await response.json().catch(() => null)
        throw new Error(
          errorData?.error || `Failed to fetch directory: ${response.status}`
        )
      }

      const data = await response.json()

      if (!data.items || !Array.isArray(data.items)) {
        throw new Error('Invalid response format')
      }

      // Sort: directories first, then by name descending (newest/highest first)
      items = data.items.sort((a: LocalItem, b: LocalItem) => {
        if (a.type !== b.type) return a.type === 'dir' ? -1 : 1
        return b.name.localeCompare(a.name)
      })

      if (items.length === 0) {
        error = 'No files or folders found'
      }
    } catch (e) {
      error = e instanceof Error ? e.message : 'Unknown error'
    } finally {
      loading = false
    }
  }

  // Load directory when localPath changes
  $effect(() => {
    loadDirectory()
  })
</script>

<div class="space-y-4">
  <div class="flex items-center gap-2 text-sm text-gray-400">
    <span>📁</span>
    <span class="font-mono">{localPath || '(root)'}</span>
    <span class="text-xs bg-purple-900/30 text-purple-300 px-2 py-0.5 rounded">
      local
    </span>
  </div>

  {#if loading}
    <div class="text-gray-400">Loading directory...</div>
  {:else if error}
    <div class="text-red-400 bg-red-900/20 p-4 rounded">{error}</div>
  {:else}
    <div class="space-y-1">
      {#if parentPath !== null}
        <a
          href={buildAppUrl(parentPath, true)}
          class="block p-3 rounded hover:bg-gray-800 transition-colors"
        >
          <div class="flex items-center gap-3">
            <span class="text-xl">📁</span>
            <span class="text-gray-300 font-mono">..</span>
          </div>
        </a>
      {/if}

      {#each items as item}
        <a
          href={buildAppUrl(item.path, item.type === 'dir')}
          class="block p-3 rounded hover:bg-gray-800 transition-colors"
        >
          <div class="flex items-center gap-3">
            {#if item.type === 'dir'}
              <span class="text-xl">📁</span>
              <span class="text-gray-300 font-mono">{item.name}/</span>
            {:else}
              <span class="text-xl">
                {#if item.name.endsWith('.json')}
                  📄
                {:else if item.name.endsWith('.py')}
                  🐍
                {:else if item.name.endsWith('.js') || item.name.endsWith('.ts')}
                  📜
                {:else if item.name.endsWith('.md')}
                  📝
                {:else}
                  📄
                {/if}
              </span>
              <span class="text-gray-300 font-mono">{item.name}</span>
              {@const timestampInfo = getTimestampInfo(item.name)}
              {#if timestampInfo}
                <span class="text-xs text-gray-500 ml-2">
                  {timestampInfo.dateTime} <span class={timestampInfo.colorClass}>({timestampInfo.age})</span>
                </span>
              {/if}
            {/if}
          </div>
        </a>
      {/each}
    </div>
  {/if}
</div>
