import { useEffect, useRef, useCallback } from 'react'
import { Editor, createShapeId, createBindingId, TLShapeId } from 'tldraw'

const BRIDGE_URL = 'ws://localhost:3100'
const RECONNECT_MIN = 500
const RECONNECT_MAX = 10_000

interface BridgeMessage {
  type: string
  id: string
  payload?: Record<string, unknown>
}

type ConnectionState = 'connecting' | 'connected' | 'disconnected'

/** Dispatches a custom event so the UI can show connection state */
function emitState(state: ConnectionState) {
  window.dispatchEvent(new CustomEvent('bridge-state', { detail: state }))
}

export function useBridge(editor: Editor | null) {
  const wsRef = useRef<WebSocket | null>(null)
  const reconnectRef = useRef<ReturnType<typeof setTimeout>>()
  const backoffRef = useRef(RECONNECT_MIN)
  const editorRef = useRef(editor)
  editorRef.current = editor

  const connect = useCallback(() => {
    if (!editorRef.current) return

    // Prevent double connections
    if (wsRef.current?.readyState === WebSocket.OPEN ||
        wsRef.current?.readyState === WebSocket.CONNECTING) {
      return
    }

    emitState('connecting')
    const ws = new WebSocket(BRIDGE_URL)
    wsRef.current = ws

    ws.onopen = () => {
      console.log('[bridge] connected')
      backoffRef.current = RECONNECT_MIN
      emitState('connected')
    }

    ws.onmessage = (event) => {
      const ed = editorRef.current
      if (!ed) return
      try {
        const msg: BridgeMessage = JSON.parse(event.data)
        const response = handleMessage(ed, msg)
        if (response !== undefined) {
          ws.send(JSON.stringify({ type: 'response', id: msg.id, data: response }))
        }
      } catch (err) {
        console.error('[bridge] message error:', err)
        ws.send(JSON.stringify({
          type: 'response',
          id: (JSON.parse(event.data) as BridgeMessage).id,
          data: { error: String(err) },
        }))
      }
    }

    ws.onclose = () => {
      wsRef.current = null
      emitState('disconnected')
      // Exponential backoff with jitter
      const delay = Math.min(backoffRef.current * (1 + Math.random() * 0.3), RECONNECT_MAX)
      backoffRef.current = Math.min(backoffRef.current * 1.5, RECONNECT_MAX)
      reconnectRef.current = setTimeout(connect, delay)
    }

    ws.onerror = () => {
      ws.close()
    }
  }, []) // stable — uses refs for mutable state

  // Connect when editor becomes available
  useEffect(() => {
    if (editor) connect()
    return () => {
      clearTimeout(reconnectRef.current)
      wsRef.current?.close()
      wsRef.current = null
    }
  }, [editor, connect])
}

// --- ID helpers ---

let counter = 0
function uid(): string {
  return `${Date.now().toString(36)}${(counter++).toString(36)}${Math.random().toString(36).slice(2, 6)}`
}

function toShapeId(raw: string): TLShapeId {
  return raw.startsWith('shape:') ? raw as TLShapeId : createShapeId(raw)
}

// --- Message handler ---

function handleMessage(editor: Editor, msg: BridgeMessage): unknown {
  switch (msg.type) {
    case 'createShapes': {
      const { shapes } = msg.payload as { shapes: Array<Record<string, unknown>> }
      if (!Array.isArray(shapes)) return { error: 'shapes must be an array' }
      const created = shapes.map((s) => ({
        ...s,
        id: s.id ? toShapeId(s.id as string) : createShapeId(uid()),
      }))
      editor.run(() => { editor.createShapes(created) })
      return { ids: created.map((s) => s.id) }
    }

    case 'updateShapes': {
      const { shapes } = msg.payload as { shapes: Array<Record<string, unknown>> }
      if (!Array.isArray(shapes)) return { error: 'shapes must be an array' }
      const updates = shapes.map((s) => ({
        ...s,
        id: toShapeId(s.id as string),
      }))
      editor.run(() => { editor.updateShapes(updates) })
      return { ok: true }
    }

    case 'deleteShapes': {
      const { ids } = msg.payload as { ids: string[] }
      if (!Array.isArray(ids)) return { error: 'ids must be an array' }
      editor.deleteShapes(ids.map(toShapeId))
      return { ok: true }
    }

    case 'createArrow': {
      const { from, to, text = '' } = msg.payload as {
        from: string; to: string; text?: string
      }
      if (!from || !to) return { error: 'from and to are required' }
      const fromId = toShapeId(from)
      const toId = toShapeId(to)

      // Verify both shapes exist
      if (!editor.getShape(fromId)) return { error: `shape not found: ${from}` }
      if (!editor.getShape(toId)) return { error: `shape not found: ${to}` }

      const arrowId = createShapeId(uid())

      editor.run(() => {
        editor.createShape({
          id: arrowId,
          type: 'arrow',
          props: { text: text || '' },
        })
        editor.createBindings([
          {
            id: createBindingId(uid()),
            type: 'arrow',
            fromId: arrowId,
            toId: fromId,
            props: {
              terminal: 'start',
              normalizedAnchor: { x: 0.5, y: 0.5 },
              isExact: false,
              isPrecise: false,
            },
          },
          {
            id: createBindingId(uid()),
            type: 'arrow',
            fromId: arrowId,
            toId: toId,
            props: {
              terminal: 'end',
              normalizedAnchor: { x: 0.5, y: 0.5 },
              isExact: false,
              isPrecise: false,
            },
          },
        ])
      })
      return { id: arrowId }
    }

    case 'getShapes': {
      const shapes = editor.getCurrentPageShapes()
      return {
        shapes: shapes.map((s) => ({
          id: s.id,
          type: s.type,
          x: s.x,
          y: s.y,
          rotation: s.rotation,
          props: s.props,
          parentId: s.parentId,
        })),
      }
    }

    case 'clear': {
      const allShapes = editor.getCurrentPageShapes()
      if (allShapes.length > 0) {
        editor.deleteShapes(allShapes.map((s) => s.id))
      }
      return { ok: true, deleted: allShapes.length }
    }

    case 'zoomToFit': {
      editor.zoomToFit({ animation: { duration: 300 } })
      return { ok: true }
    }

    case 'selectAll': {
      editor.selectAll()
      return { ok: true }
    }

    case 'getSnapshot': {
      return editor.store.getStoreSnapshot()
    }

    default:
      return { error: `unknown type: ${msg.type}` }
  }
}
