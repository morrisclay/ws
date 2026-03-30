import { useState, useEffect } from 'react'
import { Tldraw, Editor } from 'tldraw'
import 'tldraw/tldraw.css'
import { useBridge } from './hooks/useBridge'

export default function App() {
  const [editor, setEditor] = useState<Editor | null>(null)
  const [bridgeState, setBridgeState] = useState<string>('disconnected')

  useBridge(editor)

  useEffect(() => {
    const handler = (e: Event) => {
      setBridgeState((e as CustomEvent).detail)
    }
    window.addEventListener('bridge-state', handler)
    return () => window.removeEventListener('bridge-state', handler)
  }, [])

  return (
    <div className="canvas-root">
      <Tldraw
        persistenceKey="canvas"
        onMount={(editor) => setEditor(editor)}
      />
      <div
        className="bridge-indicator"
        data-state={bridgeState}
        title={`Bridge: ${bridgeState}`}
      />
    </div>
  )
}
