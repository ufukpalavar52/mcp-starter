# 04 — SSH

## Host key verification failed against a legitimate server

`handshake failed: ssh: host key mismatch`, against a host that was exactly who it
said it was.

A pinned key says **which** key to expect; it does not say which **kind** to ask
for. A server usually offers several host keys — ed25519, rsa, ecdsa — and the
client takes whichever the server prefers. Pin the ed25519 key, let the server
hand over its rsa one, and the comparison fails.

`hostKeyCallback` now returns the algorithm alongside the callback, and the client
config sets `HostKeyAlgorithms` to it: ask for the type that was pinned, which is
the only type that can possibly match.

`ssh.InsecureIgnoreHostKey` is not an option here and the code says why: this
service authenticates with a private key and then runs whatever the job says on
the other end, so anyone who can answer for the host gets both the credential and
the command. A missing key is a configuration error, not a reason to proceed.

## Two different keys, routinely confused

| | What it is for | Where it goes |
|---|---|---|
| **Host key** (the server's public key) | proves the machine is the right one | the action's `Host keys` field |
| **User key** (your private key) | proves mcp-action may log in | the sealed `Private key` secret |

Both mistakes happened while setting this up: the user key's public half was
pasted into the host key field, and then the host key's **fingerprint** was pasted
instead of the key. The field wants an `authorized_keys` line —
`ssh-ed25519 AAAA…` — with no address in front of it, because
`ssh.ParseAuthorizedKey` reads it.

The fingerprint (`SHA256:…`) is for comparing by eye against
`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` on the server. Fetching a host
key over the network and pinning it unseen protects against nothing.

## `sudo` was decorative

The panel had a "Run the command with sudo" box since the SSH action existed. It
was stored, sent to the planner, put in the job payload — and then nothing read
it. Every command ran as the connecting user, and an install that needed root
failed with a permission error that read like a problem with the server.

It is now applied by the executor, **after** the guardrails and immediately before
running. That order is the point: an action's allowlist is written against the
command itself, so a prefix of `systemctl` does not match `sudo systemctl`. Adding
the escalation before the check would have the very list that authorised a command
refuse it.

Two details:

- Not added twice. A model told the host needs root writes `sudo` itself, and the
  flag then made it `sudo sudo dnf install …`. That runs, which is the problem: it
  works, so nobody looks, and the recorded command is not the one anybody wrote.
- The `cd` stays outside the escalation. A directory the connecting user cannot
  enter is a mistake worth seeing, not one to escalate past.

## Verified by

`ssh_hostkey_test.go` — the pinned algorithm is the one requested.

`ssh_shape_test.go` — sudo reaches the command, is not added twice, `sudoedit` is
not mistaken for it, the working directory is quoted and entered as the connecting
user, and `/` adds nothing.

`test_api.py` — the job says the command needs root, and the command itself is
**not** prefixed there.
