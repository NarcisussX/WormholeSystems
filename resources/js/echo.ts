// resources/js/echo.ts
import Echo from 'laravel-echo'
import Pusher from 'pusher-js'

// keep this untyped so we don't pull Echo's generic into the Window type
declare global {
  interface Window { Echo: any }
}

// Echo expects window.Pusher to exist
;(window as any).Pusher = Pusher

const env = import.meta.env as any

const key =
  env.VITE_REVERB_APP_KEY ??
  env.VITE_PUSHER_APP_KEY

const host =
  env.VITE_REVERB_HOST ??
  env.VITE_PUSHER_HOST ??
  window.location.hostname

const scheme =
  env.VITE_REVERB_SCHEME ??
  env.VITE_PUSHER_SCHEME ??
  (location.protocol === 'https:' ? 'https' : 'http')

const port = Number(
  env.VITE_REVERB_PORT ??
  env.VITE_PUSHER_PORT ??
  (scheme === 'https' ? 443 : 80)
)

const basePath = String(env.VITE_REVERB_PATH ?? '/reverb').replace(/\/+$/, '')

// avoid TS generics by constructing via any
const EchoCtor: any = Echo
window.Echo = new EchoCtor({
  broadcaster: 'reverb',
  key,
  wsHost: host,
  wsPort: port,
  wssPort: port,
  forceTLS: scheme === 'https',
  enabledTransports: ['ws', 'wss'],
  // Reverb is mounted under /reverb -> /reverb/app websocket endpoint
  wsPath: `${basePath}/app`,
})
