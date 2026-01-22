import type { Plugin } from 'vite'
import fs from 'fs'
import path from 'path'

interface DirectoryItem {
  name: string
  path: string
  type: 'file' | 'dir'
}

/**
 * Vite plugin that provides a directory listing API for local development
 * GET /api/local/list?path=relative/path/to/dir
 */
export function localDirectoryListing(): Plugin {
  return {
    name: 'local-directory-listing',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        if (!req.url?.startsWith('/api/local/list')) {
          return next()
        }

        const url = new URL(req.url, `http://${req.headers.host}`)
        const relativePath = url.searchParams.get('path') || ''

        try {
          // Resolve path relative to project root
          const projectRoot = server.config.root
          const fullPath = path.resolve(projectRoot, relativePath)

          // Security: ensure path is within project root
          if (!fullPath.startsWith(projectRoot)) {
            res.statusCode = 403
            res.end(JSON.stringify({ error: 'Access denied' }))
            return
          }

          // Check if path exists and is a directory
          const stats = fs.statSync(fullPath)
          if (!stats.isDirectory()) {
            res.statusCode = 400
            res.end(JSON.stringify({ error: 'Not a directory' }))
            return
          }

          // Read directory contents
          const entries = fs.readdirSync(fullPath, { withFileTypes: true })

          const items: DirectoryItem[] = entries
            .map((entry) => {
              // Strip trailing slash to avoid double slashes
              const basePath = relativePath.replace(/\/$/, '')
              const itemPath = basePath ? `${basePath}/${entry.name}` : entry.name

              return {
                name: entry.name,
                path: itemPath,
                type: entry.isDirectory() ? 'dir' : 'file',
              } as DirectoryItem
            })
            // Sort: directories first, then alphabetically
            .sort((a, b) => {
              if (a.type !== b.type) return a.type === 'dir' ? -1 : 1
              return a.name.localeCompare(b.name)
            })

          res.setHeader('Content-Type', 'application/json')
          res.end(JSON.stringify({ items }))
        } catch (error) {
          res.statusCode = 500
          res.end(
            JSON.stringify({
              error: error instanceof Error ? error.message : 'Unknown error',
            })
          )
        }
      })
    },
  }
}
