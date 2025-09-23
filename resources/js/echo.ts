// resources/js/echo.ts
import Echo from 'laravel-echo'
import Pusher from 'pusher-js'

declare global {
  interface Window { Echo: Echo }
  // allow assigning Pusher for laravel-echo
  // eslint-disable-next-line no-var
  var Pusher: any
}

const key =
  (import.meta.env as any).VITE_REVERB_APP_KEY ??
  (import.meta.env as any).VITE_PUSHER_APP_KEY

const host =
  (import.meta.env as any).VITE_REVERB_HOST ??
  (import.meta.env as any).VITE_PUSHER_HOST ??
  window.location.hostname

const scheme =
  (import.meta.env as any).VITE_REVERB_SCHEME ??
  (import.meta.env as any).VITE_PUSHER_SCHEME ??
  (location.protocol === 'https:' ? 'https' : 'http')

const port = Number(
  (import.meta.env as any).VITE_REVERB_PORT ??
  (import.meta.env as any).VITE_PUSHER_PORT ??
  (scheme === 'https' ? 443 : 80)
)

// IMPORTANT: we proxy Reverb under /reverb -> upstream reverb:8080
const basePath = ((import.meta.env as any).VITE_REVERB_PATH ?? '/reverb') as string

;(window as any).Pusher = Pusher

window.Echo = new Echo({
  broadcaster: 'reverb',
  key,
  wsHost: host,
  wsPort: port,
  wssPort: port,
  forceTLS: scheme === 'https',
  enabledTransports: ['ws', 'wss'],
  // Echo’s default is "/app"; we’re under "/reverb/app"
  wsPath: `${basePath.replace(/\/+$/, '')}/app`,
})
