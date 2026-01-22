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
 * GET /api/local/file?path=relative/path/to/file
 */
export function localDirectoryListing(): Plugin {
  return {
    name: 'local-directory-listing',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        // Handle directory listing
        if (req.url?.startsWith('/api/local/list')) {
          handleDirectoryListing(req, res, server)
          return
        }

        // Handle file serving
        if (req.url?.startsWith('/api/local/file')) {
          handleFileServing(req, res, server)
          return
        }

        next()
      })
    },
  }

  function handleDirectoryListing(req: any, res: any, server: any) {
    if (!req.url?.startsWith('/api/local/list')) {
      return
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
  }

  function handleFileServing(req: any, res: any, server: any) {
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

      // Check if path exists and is a file
      const stats = fs.statSync(fullPath)
      if (!stats.isFile()) {
        res.statusCode = 400
        res.end(JSON.stringify({ error: 'Not a file' }))
        return
      }

      // Read and serve file
      const content = fs.readFileSync(fullPath, 'utf-8')

      // Set content type based on file extension
      const ext = path.extname(fullPath).toLowerCase()
      const contentType = ext === '.json' ? 'application/json' : 'text/plain'

      res.setHeader('Content-Type', contentType)
      res.end(content)
    } catch (error) {
      res.statusCode = 500
      res.end(
        JSON.stringify({
          error: error instanceof Error ? error.message : 'Unknown error',
        })
      )
    }
  }
}
