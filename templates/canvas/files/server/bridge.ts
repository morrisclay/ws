import express, { Request, Response } from 'express'
import cors from 'cors'
import http from 'http'
import { WebSocketServer, WebSocket } from 'ws'

const app = express()
app.use(cors())
app.use(express.json({ limit: '10mb' }))

const server = http.createServer(app)
const wss = new WebSocketServer({ server })

// --- WebSocket management ---

const clients = new Set<WebSocket>()
const pending = new Map<string, {
  resolve: (data: unknown) => void
  timer: ReturnType<typeof setTimeout>
}>()

wss.on('connection', (ws) => {
  clients.add(ws)
  console.log(`[bridge] client connected (${clients.size} total)`)

  ws.on('message', (raw) => {
    try {
      const msg = JSON.parse(raw.toString())
      if (msg.type === 'response' && msg.id && pending.has(msg.id)) {
        const { resolve, timer } = pending.get(msg.id)!
        clearTimeout(timer)
        pending.delete(msg.id)
        resolve(msg.data)
      }
    } catch {
      // ignore malformed
    }
  })

  ws.on('close', () => {
    clients.delete(ws)
    console.log(`[bridge] client disconnected (${clients.size} total)`)
  })
})

/**
 * Send a message to the first connected canvas client and wait for its response.
 * Only one client gets the message to avoid duplicate responses.
 */
function send(msg: Record<string, unknown>): Promise<unknown> {
  return new Promise((resolve, reject) => {
    // Find the first open client
    let target: WebSocket | null = null
    for (const c of clients) {
      if (c.readyState === WebSocket.OPEN) { target = c; break }
    }
    if (!target) {
      return reject(new Error('No canvas connected'))
    }

    const id = crypto.randomUUID()
    const timer = setTimeout(() => {
      pending.delete(id)
      reject(new Error('Timeout — canvas did not respond within 5s'))
    }, 5000)

    pending.set(id, { resolve, timer })
    target.send(JSON.stringify({ ...msg, id }))
  })
}

/** Wrap an async handler so errors become JSON responses */
function api(fn: (req: Request, res: Response) => Promise<void>) {
  return async (req: Request, res: Response) => {
    try {
      await fn(req, res)
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err)
      const status = message.includes('No canvas connected') ? 503 : 500
      res.status(status).json({ error: message })
    }
  }
}

// --- Health ---

app.get('/api/health', (_req, res) => {
  res.json({ ok: true, clients: clients.size })
})

// --- Shape CRUD ---

app.post('/api/shapes', api(async (req, res) => {
  const { shapes } = req.body
  if (!Array.isArray(shapes)) {
    res.status(400).json({ error: 'body must contain "shapes" array' })
    return
  }
  const result = await send({ type: 'createShapes', payload: { shapes } })
  res.json(result)
}))

app.patch('/api/shapes', api(async (req, res) => {
  const { shapes } = req.body
  if (!Array.isArray(shapes)) {
    res.status(400).json({ error: 'body must contain "shapes" array' })
    return
  }
  const result = await send({ type: 'updateShapes', payload: { shapes } })
  res.json(result)
}))

app.delete('/api/shapes', api(async (req, res) => {
  const { ids } = req.body
  if (!Array.isArray(ids)) {
    res.status(400).json({ error: 'body must contain "ids" array' })
    return
  }
  const result = await send({ type: 'deleteShapes', payload: { ids } })
  res.json(result)
}))

app.get('/api/shapes', api(async (_req, res) => {
  const result = await send({ type: 'getShapes' })
  res.json(result)
}))

// --- Convenience endpoints ---

app.post('/api/note', api(async (req, res) => {
  const { text, x = 200, y = 200, color = 'yellow' } = req.body
  if (typeof text !== 'string' || !text) {
    res.status(400).json({ error: '"text" is required' })
    return
  }
  const result = await send({
    type: 'createShapes',
    payload: {
      shapes: [{
        type: 'note',
        x: Number(x), y: Number(y),
        props: { text, color, size: 'm' },
      }],
    },
  })
  res.json(result)
}))

app.post('/api/box', api(async (req, res) => {
  const { text = '', x = 200, y = 200, w = 200, h = 100, color = 'black' } = req.body
  const result = await send({
    type: 'createShapes',
    payload: {
      shapes: [{
        type: 'geo',
        x: Number(x), y: Number(y),
        props: { text, geo: 'rectangle', w: Number(w), h: Number(h), color },
      }],
    },
  })
  res.json(result)
}))

app.post('/api/text', api(async (req, res) => {
  const { text, x = 200, y = 200, size = 'm', color = 'black' } = req.body
  if (typeof text !== 'string' || !text) {
    res.status(400).json({ error: '"text" is required' })
    return
  }
  const result = await send({
    type: 'createShapes',
    payload: {
      shapes: [{
        type: 'text',
        x: Number(x), y: Number(y),
        props: { text, size, color },
      }],
    },
  })
  res.json(result)
}))

app.post('/api/arrow', api(async (req, res) => {
  const { from, to, text = '' } = req.body
  if (!from || !to) {
    res.status(400).json({ error: '"from" and "to" shape IDs are required' })
    return
  }
  const result = await send({ type: 'createArrow', payload: { from, to, text } })
  res.json(result)
}))

// --- Canvas operations ---

app.post('/api/clear', api(async (_req, res) => {
  const result = await send({ type: 'clear' })
  res.json(result)
}))

app.post('/api/zoom-to-fit', api(async (_req, res) => {
  const result = await send({ type: 'zoomToFit' })
  res.json(result)
}))

app.get('/api/snapshot', api(async (_req, res) => {
  const result = await send({ type: 'getSnapshot' })
  res.json(result)
}))

// --- Batch operations ---

app.post('/api/batch', api(async (req, res) => {
  const { operations } = req.body
  if (!Array.isArray(operations)) {
    res.status(400).json({ error: 'body must contain "operations" array' })
    return
  }

  const results: unknown[] = []
  for (const op of operations) {
    try {
      const result = await send({ type: op.type, payload: op.payload })
      results.push({ ok: true, result })
    } catch (err: unknown) {
      results.push({ ok: false, error: err instanceof Error ? err.message : String(err) })
    }
  }
  res.json({ results })
}))

// --- Start with graceful shutdown ---

const PORT = parseInt(process.env.BRIDGE_PORT || '3100', 10)
server.listen(PORT, () => {
  console.log(`[bridge] listening on http://localhost:${PORT}`)
})

function shutdown() {
  console.log('\n[bridge] shutting down...')
  for (const ws of clients) ws.close()
  for (const { timer } of pending.values()) clearTimeout(timer)
  pending.clear()
  server.close(() => process.exit(0))
  setTimeout(() => process.exit(1), 3000)
}
process.on('SIGINT', shutdown)
process.on('SIGTERM', shutdown)
