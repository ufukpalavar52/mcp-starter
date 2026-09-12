# 02 — The router and central configuration

## The routing model moved to DeepInfra

The model that decides which tool answers a prompt is now
`Qwen/Qwen3-235B-A22B-Instruct-2507` on DeepInfra.

It reads that from the **config server** rather than from mcp-server's own
`.env`: provider, endpoint, model name and key live in
`config-repo/mcp-server.yml`. Changing the model no longer means editing a
service's files.

That needed the Python equivalent of what the Go clients already did —
`app/remote_config.py`: fetch `/{application}/{profile}`, resolve `${NAME:default}`
placeholders, and **let a local value win**. `/health` reports which source was
used, because "silently fell back to local defaults while the config server was
down" is the hardest kind of fault to notice.

## The config server was handing out every secret, unauthenticated

`SecurityConfiguration` carried `permitAll("/actuator/health")`. There is no
actuator on the classpath; what served that path was the config server's own
`/{application}/{profile}` route. So: `DB_PASSWORD`, `JWT_SECRET_KEY`,
`MCP_CIPHER_TOKEN`, the broker and redis passwords, to anyone who asked.

The rule was removed — `anyRequest().authenticated()`.

The existing test had not caught it because it asserted only that the path
returned **200**, which is precisely what the leak did. It was replaced by
`theHealthPathIsNotAWayInEither`: expects 401 **and reads the body** to confirm
those three secrets are not in it.

> Watch what a test actually asserts. A status code does not say the content was
> right.

## CORS became central

The gateway allowed only `localhost:3000`; with the panel on 3111 every request
died in the browser and the error read as "server not found". `CORS_ORIGINS` now
comes from the config server.

## Timeout

`MCP_SERVER_TIMEOUT` was 30 seconds and was cutting off model calls. Now 120.

## Verified by

`ServedConfigurationTest` — nine tests covering where each served property comes
from, and that an unauthenticated response carries no secret in its body.

On the mcp-server side, the `remote_config` tests — placeholder resolution, local
values winning, and starting up with no config server at all.
