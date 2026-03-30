# {{name}} — Canvas Workspace

## How This Works

You have a live TLDraw whiteboard in the right pane. A bridge server connects you to it. You draw on it by running `./bin/canvas` commands or `curl` against localhost:3100.

A green dot in the top-right of the canvas = bridge connected. Red = disconnected.

## IMPORTANT: Use the Canvas

**The canvas is your primary visual output.** Every response that involves structure, relationships, flow, comparison, or planning should produce a drawing. Default to drawing — only skip it for pure text answers (e.g., "what does this variable do?").

On session start, verify the bridge is up:
```bash
./bin/canvas health
```

## Commands

**Always use `./bin/canvas`** (not bare `canvas` — it's not on PATH in this shell).

```bash
# Create shapes — all return {"ids":["shape:..."]}
./bin/canvas note "text" [x] [y] [color]
./bin/canvas box  "text" [x] [y] [w] [h] [color]
./bin/canvas text "text" [x] [y]
./bin/canvas arrow <from-id> <to-id> [label]

# Update / Delete
./bin/canvas update <id> '{"props":{"text":"new","color":"red"}}'
./bin/canvas delete <id> [id2...]

# Read what's on the canvas (including user drawings)
./bin/canvas shapes
./bin/canvas shapes | jq '.shapes[] | {id, type, text: .props.text}'

# Canvas control
./bin/canvas clear
./bin/canvas zoom          # zoom camera to fit — ALWAYS run after drawing
./bin/canvas health
```

**Colors:** `black`, `grey`, `light-violet`, `violet`, `blue`, `light-blue`, `yellow`, `orange`, `green`, `light-green`, `light-red`, `red`, `white`

## Coordinate System

- Origin (0,0) = top-left. X → right, Y → down.
- Default box: 200x100. Default note: ~200x200.
- Leave ~50px gaps between shapes.
- Typical diagram region: 1200x800 starting at (100, 100).
- **Always run `./bin/canvas zoom` after drawing** so the user sees everything.

## Patterns

### Flowchart
```bash
A=$(./bin/canvas box "Start" 300 100 160 80 green | jq -r '.ids[0]')
B=$(./bin/canvas box "Process" 300 250 160 80 blue | jq -r '.ids[0]')
C=$(./bin/canvas box "End" 300 400 160 80 red | jq -r '.ids[0]')
./bin/canvas arrow "$A" "$B"
./bin/canvas arrow "$B" "$C"
./bin/canvas zoom
```

### Brainstorm
```bash
./bin/canvas note "Problem" 100 100 light-red
./bin/canvas note "Idea A" 350 100 yellow
./bin/canvas note "Idea B" 600 100 yellow
./bin/canvas note "Idea C" 850 100 yellow
./bin/canvas note "Decision" 350 350 light-green
./bin/canvas zoom
```

### Architecture Diagram
```bash
UI=$(./bin/canvas box "Frontend" 100 100 180 80 blue | jq -r '.ids[0]')
API=$(./bin/canvas box "API Server" 400 100 180 80 green | jq -r '.ids[0]')
DB=$(./bin/canvas box "Database" 700 100 180 80 violet | jq -r '.ids[0]')
./bin/canvas arrow "$UI" "$API" "REST"
./bin/canvas arrow "$API" "$DB" "SQL"
./bin/canvas zoom
```

### Comparison / Pros-Cons
```bash
./bin/canvas box "Option A" 100 100 250 60 blue
./bin/canvas note "Pro: Fast" 100 200 light-green
./bin/canvas note "Con: Complex" 100 430 light-red
./bin/canvas box "Option B" 450 100 250 60 violet
./bin/canvas note "Pro: Simple" 450 200 light-green
./bin/canvas note "Con: Slow" 450 430 light-red
./bin/canvas zoom
```

### Reading User Drawings
The user can draw manually. Check what's there before drawing over it:
```bash
./bin/canvas shapes | jq '.shapes[] | {id, type, text: .props.text}'
```

### Batch (one request, many shapes)
```bash
./bin/canvas batch '[
  {"type":"createShapes","payload":{"shapes":[
    {"type":"note","x":100,"y":100,"props":{"text":"One","color":"yellow"}},
    {"type":"note","x":350,"y":100,"props":{"text":"Two","color":"light-blue"}}
  ]}},
  {"type":"zoomToFit"}
]'
```

## When to Draw

| User intent | What to draw |
|---|---|
| "Explain how X works" | Architecture/flow diagram |
| "Compare A vs B" | Side-by-side boxes with notes |
| "Plan the implementation" | Flowchart or phased diagram |
| "Brainstorm ideas for..." | Sticky notes, grouped by theme |
| "Debug this issue" | Call chain / data flow |
| "What's the structure of..." | Component/entity diagram |
| "Help me think through..." | Mind map or decision tree |

If you drew something, mention it in your text response: "I've sketched the architecture on the canvas."

## Direct HTTP API

For edge cases the CLI doesn't cover:

```
POST   /api/shapes       {"shapes":[...]}           → {"ids":[...]}
PATCH  /api/shapes       {"shapes":[{id,props}...]}  → {"ok":true}
DELETE /api/shapes       {"ids":["shape:..."]}        → {"ok":true}
GET    /api/shapes                                    → {"shapes":[...]}
POST   /api/note         {"text","x","y","color"}     → {"ids":[...]}
POST   /api/box          {"text","x","y","w","h"}     → {"ids":[...]}
POST   /api/text         {"text","x","y"}             → {"ids":[...]}
POST   /api/arrow        {"from","to","text"}         → {"id":"shape:..."}
POST   /api/clear                                     → {"ok":true}
POST   /api/zoom-to-fit                               → {"ok":true}
POST   /api/batch        {"operations":[...]}         → {"results":[...]}
GET    /api/snapshot                                  → full store snapshot
GET    /api/health                                    → {"ok":true,"clients":N}
```

Geo types: `rectangle`, `ellipse`, `diamond`, `triangle`, `pentagon`, `hexagon`, `octagon`, `star`, `cloud`, `arrow-right`, `arrow-left`, `arrow-up`, `arrow-down`

## Structure

- `src/` — TLDraw React app (Vite, port 5173)
- `server/` — Bridge server (Express + WebSocket, port 3100)
- `bin/canvas` — CLI tool

## Journal

```bash
ws journal {{name}} --finding "..."
ws journal {{name}} --decision "..."
ws journal {{name}} --note "..."
```
