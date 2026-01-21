<script lang="ts">
  interface GitHubItem {
    name: string
    path: string
    type: 'file' | 'dir'
  }

  interface Props {
    githubPath: string // e.g., "g0t4/dataset-gfy/master/semantic_grep_auto_context/fims"
  }

  let { githubPath }: Props = $props()

  let items: GitHubItem[] = $state([])
  let loading = $state(true)
  let error = $state<string | null>(null)

  // Parse github path into components
  const parsed = $derived.by(() => {
    const parts = githubPath.split('/')
    if (parts.length < 3) return null

    return {
      owner: parts[0],
      repo: parts[1],
      branch: parts[2],
      path: parts.slice(3).join('/'),
      fullPath: githubPath,
    }
  })

  // Build github.com URL for scraping
  const githubUrl = $derived(
    parsed
      ? `https://github.com/${parsed.owner}/${parsed.repo}/tree/${parsed.branch}/${parsed.path}`
      : null
  )

  // Build app URL for navigation
  function buildAppUrl(itemPath: string, isDir: boolean): string {
    if (!parsed) return ''
    const newGithubPath = `${parsed.owner}/${parsed.repo}/${parsed.branch}/${itemPath}`
    return `${window.location.pathname}?github=${encodeURIComponent(newGithubPath)}${window.location.hash}`
  }

  // Get parent directory path
  const parentPath = $derived.by(() => {
    if (!parsed || !parsed.path) return null
    const parts = parsed.path.split('/').filter(Boolean)
    if (parts.length === 0) return null
    parts.pop()
    const parentDir = parts.join('/')
    return `${parsed.owner}/${parsed.repo}/${parsed.branch}/${parentDir}`
  })

  async function loadDirectory() {
    loading = true
    error = null
    items = []

    if (!parsed) {
      error = 'Invalid GitHub path'
      loading = false
      return
    }

    try {
      // Use jsDelivr API for directory listings (great CORS support, no rate limits)
      // https://data.jsdelivr.com/v1/packages/gh/user/repo@branch/files/path
      const pathSegment = parsed.path ? `/${parsed.path}` : ''
      const apiUrl = `https://data.jsdelivr.com/v1/packages/gh/${parsed.owner}/${parsed.repo}@${parsed.branch}/files${pathSegment}`

      const response = await fetch(apiUrl)

      if (!response.ok) {
        throw new Error(`Failed to fetch directory: ${response.status}`)
      }

      const data = await response.json()

      // jsDelivr returns {files: [...]} structure
      if (data.files && Array.isArray(data.files)) {
        items = data.files
          .map((item: any) => {
            // item has: {name, hash, size, time} for files
            // item has: {name, hash, time, type: "directory"} for dirs
            const isDir = item.type === 'directory'
            const fullPath = parsed.path ? `${parsed.path}/${item.name}` : item.name

            return {
              name: item.name,
              path: fullPath,
              type: isDir ? 'dir' : 'file',
            }
          })
          .sort((a, b) => {
            // Directories first, then alphabetically
            if (a.type !== b.type) return a.type === 'dir' ? -1 : 1
            return a.name.localeCompare(b.name)
          })
      } else {
        throw new Error('Invalid response from jsDelivr')
      }
    } catch (e) {
      error = e instanceof Error ? e.message : 'Unknown error'
    } finally {
      loading = false
    }
  }

  // Load directory when githubPath changes
  $effect(() => {
    loadDirectory()
  })
</script>

<div class="space-y-4">
  <div class="flex items-center gap-2 text-sm text-gray-400">
    <span>📁</span>
    <span class="font-mono">{parsed?.path || '(root)'}</span>
  </div>

  {#if loading}
    <div class="text-gray-400">Loading directory...</div>
  {:else if error}
    <div class="text-red-400 bg-red-900/20 p-4 rounded">{error}</div>
  {:else}
    <div class="space-y-1">
      {#if parentPath}
        <a
          href={buildAppUrl(parentPath.split('/').slice(3).join('/'), true)}
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
              {#if item.name.endsWith('.json')}
                <span class="text-xs text-cyan-400">(thread)</span>
              {/if}
            {/if}
          </div>
        </a>
      {/each}
    </div>
  {/if}
</div>
