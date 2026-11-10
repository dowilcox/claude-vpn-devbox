# claude-vpn-devbox

Run [Claude Code](https://code.claude.com/docs) and your dev toolchain in a
Docker container whose **all** traffic goes through a VPN, via
[gluetun](https://github.com/qdm12/gluetun), while your projects stay on your
own disk and you work on them exactly as before.

```
host
 ├─ gluetun ── owns the network namespace: VPN tunnel + kill-switch firewall
 │    └─ publishes dev-server ports (3000, 5173, 8000, 8080) to 127.0.0.1
 └─ devbox ─── network_mode: service:gluetun (no network of its own)
      ├─ claude, git, gh, node/pnpm, python, (php/composer, rust, go)
      └─ $PROJECTS_DIR bind-mounted at the SAME absolute path as on the host
```

- Claude Code's API traffic, `npm install`, `pip`, `composer`, `cargo`,
  `git push`: everything leaves through the VPN.
- If the tunnel drops, gluetun's firewall blocks traffic rather than leaking
  your real IP.
- Your projects folder is mounted at the same path inside and out, so
  `devbox claude` run from `~/code/my-app` opens Claude in `~/code/my-app`
  inside the container, and Claude's per-project history lines up.

## Requirements

- Docker Engine with the Compose plugin (v2.24+), on Linux. Docker Desktop on
  macOS/Windows should work, but is untested.
- `/dev/net/tun` on the host (standard on Linux).
- A VPN account [supported by gluetun](https://github.com/qdm12/gluetun-wiki/tree/main/setup/providers)
  (Mullvad, ProtonVPN, AirVPN, PIA, NordVPN, Surfshark, Windscribe, or a
  custom WireGuard/OpenVPN config).

## Quick start

```bash
git clone https://github.com/dowilcox/claude-vpn-devbox.git
cd claude-vpn-devbox

bin/devbox init ~/code         # writes .env with your UID/GID, timezone, projects path
$EDITOR .env                   # add VPN credentials, choose toolchains
bin/devbox up                  # builds the image, starts gluetun then the devbox
bin/devbox ip                  # host IP vs. devbox IP; they should differ

ln -s "$PWD/bin/devbox" ~/.local/bin/devbox   # optional: put it on your PATH
cd ~/code/my-app && devbox claude
```

The first time, run `/login` inside Claude. It shows a URL: open it in your
browser on the host and paste the code back. The login is stored in a Docker
volume and survives rebuilds. To skip interactive login, run
`claude setup-token` anywhere and put the result in `devbox.env` as
`CLAUDE_CODE_OAUTH_TOKEN`.

### VPN examples

Mullvad / WireGuard (in `.env`):

```ini
VPN_SERVICE_PROVIDER=mullvad
VPN_TYPE=wireguard
WIREGUARD_PRIVATE_KEY=<from your Mullvad WireGuard config>
WIREGUARD_ADDRESSES=10.x.x.x/32
SERVER_COUNTRIES=USA
```

ProtonVPN / OpenVPN:

```ini
VPN_SERVICE_PROVIDER=protonvpn
VPN_TYPE=openvpn
OPENVPN_USER=<openvpn username>
OPENVPN_PASSWORD=<openvpn password>
```

Any other gluetun variable (`SERVER_HOSTNAMES`, `PORT_FORWARDING`, custom
`WIREGUARD_ENDPOINT_IP` ...) can go in an optional `.env.vpn` file, which is
passed straight through to gluetun.

## Commands

| Command | What it does |
|---|---|
| `devbox init [DIR]` | Create `.env` from `.env.example` |
| `devbox up` | Build if needed and start both containers |
| `devbox down` | Stop and remove both containers (volumes are kept) |
| `devbox claude [args]` | Run Claude Code in the current directory |
| `devbox shell [cmd]` | Open bash, or run a command, in the current directory |
| `devbox ip` | Compare your host's public IP with the devbox's |
| `devbox status` | Container status and gluetun health |
| `devbox logs [svc]` | Follow logs (gluetun by default) |
| `devbox build` | Rebuild the image from scratch (picks up a newer Claude Code) |
| `devbox restart` | Recreate the devbox; needed after gluetun restarts |

If your current directory is outside `PROJECTS_DIR`, commands start in
`PROJECTS_DIR` instead and print a note.

## Configuration

Everything lives in `.env` (see [`.env.example`](.env.example)):

| Variable | Purpose |
|---|---|
| `PROJECTS_DIR` | Absolute path of your projects folder, mounted at the same path |
| `VPN_*`, `WIREGUARD_*`, `OPENVPN_*`, `SERVER_*` | gluetun VPN settings |
| `FIREWALL_OUTBOUND_SUBNETS` | Subnets reachable *without* the VPN (Docker bridges, your LAN) |
| `BIND_ADDRESS`, `HOST_PORT_*` | Where published ports appear on the host |
| `DEVBOX_UID`, `DEVBOX_GID` | Match your host user so files you create are yours |
| `INSTALL_NODE` / `PYTHON` / `PHP` / `RUST` / `GO` / `DOCKER_CLI` | Toolchains baked into the image |
| `COMPOSE_FILE`, `DOCKER_GID` | Enable host Docker access (see below) |

Optional per-container settings go in `devbox.env` (see
[`devbox.env.example`](devbox.env.example)): git identity, `GH_TOKEN` for
`gh` and HTTPS `git push`, and `CLAUDE_CODE_OAUTH_TOKEN`. Lines you leave out
stay unset in the container.

After changing toolchain flags, run `devbox up` again (it rebuilds). After
changing VPN settings, run `docker compose up -d` and then `devbox restart`.

## Running dev servers

The devbox shares gluetun's network, so **ports are published on gluetun**,
not on the devbox. `compose.yml` publishes 3000, 5173, 8000 and 8080 to
`127.0.0.1` by default. Add more under `gluetun.ports`. If a port clashes with
something on your host, change its `HOST_PORT_*`.

Servers must listen on all interfaces inside the container:

```bash
npm run dev -- --host 0.0.0.0              # Vite
php artisan serve --host=0.0.0.0 --port=8000
python manage.py runserver 0.0.0.0:8000
uvicorn app:app --host 0.0.0.0 --port 8000
```

gluetun's own control server normally listens on `:8000`. This setup moves
it to `127.0.0.1:9997` so it doesn't collide with your app.

## Reaching services on the host

`host.docker.internal` points at the host from inside the devbox. Use it for
a database, Ollama, or anything else you run on the host. The default
`FIREWALL_OUTBOUND_SUBNETS=172.16.0.0/12` lets that traffic bypass the
tunnel. Add your LAN (for example `192.168.1.0/24`) if you need to reach
other machines.

The host service has to listen on the Docker bridge address (172.17.0.1) or
on all interfaces. A service bound only to `127.0.0.1` on the host isn't
reachable from any container.

## Project stacks that use Docker Compose

Many projects ship their own `docker-compose.yml` (app + database + cache).
Turn on host Docker access to drive them from inside the devbox:

```ini
# .env
COMPOSE_FILE=compose.yml:compose.docker.yml
DOCKER_GID=<output of: stat -c %g /var/run/docker.sock>
```

Because projects are mounted at the same path as on the host, relative bind
mounts like `./:/app` in those compose files resolve correctly.

**Containers started this way run on the host's network, not through the
VPN.** Pick an approach:

1. **Run the app in the devbox, infrastructure via compose (recommended).**
   Run the code that talks to the internet (dev server, workers, package
   installs) in the devbox. Start only databases and caches with the project's
   compose file. They rarely make outbound connections, so being off the VPN
   doesn't matter. Point the app at `host.docker.internal:<published port>`.
2. **Accept it.** If you mainly want Claude Code and package downloads on
   the VPN, the project's own containers being off it may be fine.
3. **Force the stack onto the VPN.** Add an override that gives each service
   `network_mode: container:<gluetun container name>`. Every service then
   shares one `localhost`: service-name DNS (`redis`, `db`) stops working and
   ports must not overlap. This is workable for small stacks and painful for
   big ones.

## Git and GitHub

- **Identity:** set `GIT_AUTHOR_*` and `GIT_COMMITTER_*` in `devbox.env`.
  The container's home directory isn't persisted, so `git config --global`
  doesn't survive a recreate.
- **HTTPS push to GitHub:** set `GH_TOKEN` in `devbox.env`. `gh` is
  installed and configured as git's credential helper for github.com.
- **SSH:** add a `compose.override.yml` (and include it in `COMPOSE_FILE`)
  that mounts your agent socket:

  ```yaml
  services:
    devbox:
      environment:
        SSH_AUTH_SOCK: /ssh-agent
      volumes:
        - ${SSH_AUTH_SOCK}:/ssh-agent
  ```

## Security notes

- **This is a network boundary, not a sandbox.** Your projects folder is
  mounted read-write, and the devbox user has passwordless `sudo` inside the
  container. Running `claude --dangerously-skip-permissions` here keeps
  Claude away from the rest of your host's filesystem, but not away from
  your projects.
- **Docker socket access (`compose.docker.yml`) is root-equivalent on the
  host.** With it enabled, the container is no longer a meaningful isolation
  layer. Leave it off unless you need it.
- `.env`, `.env.vpn` and `devbox.env` hold secrets and are git-ignored.
  `devbox init` creates `.env` with mode 600.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `devbox up` hangs at "waiting for gluetun" | `devbox logs`. Usually wrong VPN credentials or server filters. |
| devbox has no network after gluetun restarted | `devbox restart`. A container sharing a namespace has to be recreated when the namespace owner is. |
| Port works in the devbox but not from the host | Make sure the server listens on `0.0.0.0` and the port is under `gluetun.ports`. |
| Can't reach `host.docker.internal` | Check `FIREWALL_OUTBOUND_SUBNETS` and that the host service isn't bound only to 127.0.0.1. |
| Files created by the container are owned by root or another UID | Set `DEVBOX_UID` / `DEVBOX_GID` to `id -u` / `id -g`, then `devbox up`. |
| `permission denied` on `/var/run/docker.sock` | `DOCKER_GID` must match `stat -c %g /var/run/docker.sock`. |
| Native npm modules fail to load | They were built on the host against a different libc. Run `npm ci` inside the devbox. |
| Claude Code login or API errors only on the VPN | Pick an exit server in a region Anthropic supports. Some datacenter IPs see extra challenges. |
| Host MCP servers missing in the container | Expected. The devbox uses its own Claude config (`CLAUDE_CONFIG_DIR`). Add MCP servers there with `devbox claude mcp add ...`. |

## Files

```
compose.yml           gluetun + devbox
compose.docker.yml    optional host Docker socket access
Dockerfile            Ubuntu 24.04 + toolchains + Claude Code
.env.example          main settings (copy to .env)
devbox.env.example    optional git identity / tokens (copy to devbox.env)
bin/devbox            helper CLI
```

## License

[MIT](LICENSE)
