# Environment

What each service needs to start, as templates. **Every value here is an example**, not a
working one: the addresses and ports are the usual defaults, and anything secret reads
`change-me` or names the command that generates it. Nothing from a real installation is in
these files.

These are not the working files. The services read `.env` from their own repositories; these
say what has to be in one.

| File | Goes to | Notes |
|---|---|---|
| `mcp-config.env.example` | `mcp-config/.env` | Holds everything the other services are handed |
| `mcp-gateway.env.example` | `mcp-gateway/.env` | Only its config-server credentials |
| `mcp-server.env.example` | `mcp-server/.env` | |
| `mcp-action.env.example` | `mcp-action/.env` | |
| `mcp-cipher.env.example` | `mcp-cipher/.env` | The encryption keys live here and nowhere else |
| `mcp-panel.env.example` | `mcp-panel/.env.local` | Next.js reads `.env.local`, not `.env` |

## Setting one up

```sh
cp env/mcp-config.env.example ~/path/to/mcp-config/.env
# then fill in the blanks
```

`CONFIG_USER` / `CONFIG_PASSWORD` appear in all six: every service authenticates to
mcp-config with them, and mcp-config checks them. The same pair everywhere.

## Where the values come from

**`MCP_CIPHER_KEY_V1`** — 32 bytes, base64. Generate with
`openssl rand -base64 32`. **If this is lost, everything sealed with it is unreadable and
has to be entered again.** There is no recovery: the key exists only in the mcp-cipher
process, and it reaches neither the config server nor the database. That is the point of it.

**`JWT_SECRET_KEY`** — long and random; the same command will do. Changing it signs
everybody out.

**`MCP_CIPHER_TOKEN`**, **`PUBLISHER_TOKEN`** — shared secrets between two services. Any
long random string, the same on both sides.

**`DB_PASSWORD`**, **`REDIS_PASSWORD`**, **`QUEUE_PASSWORD`** — whatever the containers were
started with.

**`CONFIG_PASSWORD`** — mcp-config refuses to start without one, deliberately: it hands out
the database password, the JWT key and the broker password, so an empty value would leave
all of them behind a login anyone can pass.

## Keep the real files out of here

A directory of `.env` files is a directory of credentials, and this one sits beside
documentation that is meant to be readable. The `.gitignore` here refuses `.env` and
`*.env.local` for that reason; the templates are the only thing that belongs.

If you need the working values on another machine, move them the way credentials are moved
— not by copying a folder that also contains a README.
