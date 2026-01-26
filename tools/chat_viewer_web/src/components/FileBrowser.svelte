<script lang="ts">
  import { getTimestampInfo } from '../lib/timestamp-utils'

  interface GitHubItem {
    name: string
    path: string
    type: 'file' | 'dir'
    download_url?: string
  }

  interface Props {
    url: string
  }

  let { url }: Props = $props()

  let items: GitHubItem[] = $state([])
  let loading = $state(true)
  let error = $state<string | null>(null)
  let currentPath = $state('')
  let repoInfo = $state<{ owner: string; repo: string; branch: string } | null>(null)

  // Convert raw.githubusercontent.com URL to GitHub API URL
  function convertToApiUrl(rawUrl: string): string | null {
    // Example: https://raw.githubusercontent.com/g0t4/dataset-gfy/master/semantic_grep_auto_context/fims/
    const match = rawUrl.match(
      /raw\.githubusercontent\.com\/([^/]+)\/([^/]+)\/([^/]+)\/?(.*)/
    )
    if (!match) return null

    const [, owner, repo, branch, path] = match
    repoInfo = { owner, repo, branch }
    currentPath = path || ''

    // GitHub API endpoint for contents
    // https://api.github.com/repos/g0t4/dataset-gfy/contents/semantic_grep_auto_context/fims?ref=master
    const apiUrl = `https://api.github.com/repos/${owner}/${repo}/contents/${path}?ref=${branch}`
    return apiUrl
  }

  // Build a URL for navigation (for the ?url= parameter)
  function buildRawUrl(path: string): string {
    if (!repoInfo) return ''
    const { owner, repo, branch } = repoInfo
    return `https://raw.githubusercontent.com/${owner}/${repo}/${branch}/${path}`
  }

  // Build a URL for the current app with a new path
  function buildAppUrl(path: string, isDir: boolean): string {
    const rawUrl = buildRawUrl(path)
    // Add trailing slash for directories so we detect them as directories
    const finalUrl = isDir ? rawUrl + '/' : rawUrl
    return `${window.location.pathname}?url=${encodeURIComponent(finalUrl)}${window.location.hash}`
  }

  async function loadDirectory() {
    loading = true
    error = null
    items = []

    try {
      const apiUrl = convertToApiUrl(url)
      if (!apiUrl) {
        throw new Error('Invalid GitHub URL format')
      }

      const res = await fetch(apiUrl)
      if (!res.ok) {
        throw new Error(`Failed to fetch directory: ${res.status}`)
      }

      const data = await res.json()

      // GitHub API returns an array for directories
      if (Array.isArray(data)) {
        items = data
          .filter((item: any) => item.type === 'file' || item.type === 'dir')
          .sort((a: any, b: any) => {
            // Directories first, then by name descending (newest/highest first)
            if (a.type !== b.type) {
              return a.type === 'dir' ? -1 : 1
            }
            return b.name.localeCompare(a.name)
          })
      } else {
        throw new Error('URL does not point to a directory')
      }
    } catch (e) {
      error = e instanceof Error ? e.message : 'Unknown error'
    } finally {
      loading = false
    }
  }

  // Load directory when URL changes
  $effect(() => {
    loadDirectory()
  })

  // Get parent directory path for "up" navigation
  const parentPath = $derived.by(() => {
    if (!currentPath) return null
    const parts = currentPath.split('/').filter(Boolean)
    if (parts.length === 0) return null
    parts.pop()
    return parts.join('/') + '/'
  })
</script>

<div class="space-y-4">
  <div class="flex items-center gap-2 text-sm text-gray-400">
    <span>📁</span>
    <span class="font-mono">{currentPath || '(root)'}</span>
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
              {@const timestampInfo = getTimestampInfo(item.name)}
              {#if timestampInfo}
                <span class="text-xs text-gray-500 ml-2">
                  {timestampInfo.dateTime} <span class={timestampInfo.colorClass}>({timestampInfo.age})</span>
                </span>
              {/if}
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
