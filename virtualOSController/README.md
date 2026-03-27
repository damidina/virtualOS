# virtualOS Controller

Electrobun desktop controller for the existing `virtualOS` LAN remote host.

## Current shape

- Connects to an existing host endpoint such as `http://192.168.2.196:8899`
- Uses Electrobun RPC from the renderer to the Bun main process for `POST /control/*` and `GET /health`
- Loads the live frame directly from `/frame.jpg`
- Supports focus, typing, keyboard actions, click-to-control, safe open actions, and watched-repo status/pull

## Run

```bash
bun install
bun run dev
```

For HMR:

```bash
bun run dev:hmr
```

## Build

```bash
bun run build
```

Current macOS output:

- App bundle: `build/dev-macos-arm64/virtualOS Controller-dev.app`
- Zip artifact: `dist/virtualOS-Controller-dev.app.zip`

## Key files

```text
src/bun/index.ts          Electrobun main process and LAN RPC bridge
src/shared/rpc.ts         shared RPC schema and remote payload types
src/mainview/App.tsx      controller UI
src/mainview/rpc.ts       renderer-side Electrobun RPC client
```
