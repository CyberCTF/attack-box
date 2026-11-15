# Cyber CTF attack box

The machine a Cyber CTF player attacks a lab from: Kali Linux with its headless toolset and a
`player` account. The [Cyber CTF launcher](https://github.com/Cyber-Courses/Cyber-CTF-Launcher)
adds it to a lab in one of two forms, both from this repository:

| Form | What it is | Files |
| --- | --- | --- |
| Container | The `cyberctf/attack-box` image on Docker Hub, multi-arch (amd64, arm64), rebuilt weekly (Kali is a rolling release) | `Dockerfile`, `bashrc.cyberctf`, `player-account.sh`, `smoke-test.sh` |
| VM | A set-up script the launcher runs in a Kali or Debian VM | `vm/kali.sh`, `vm/toolset.sh`, `vm/desktop.sh`, `player-account.sh` |

## The VM set-up

The launcher assembles one `sh` script from these parts, in this order:

1. `vm/kali.sh`: on a Debian VM (where Kali has no image for the computer's CPU), Kali's archive
   in place of Debian's, its keyring checked against Kali's two archive keys before apt trusts it,
   keeping the VM's own kernel. It defines `$keep`, which the parts after it use.
2. `vm/toolset.sh`: Kali's headless toolset, unless the box has it already.
3. The player's account: `player-account.sh`, run by the launcher with the box's shared folder and
   password file.
4. `vm/desktop.sh`, for a box with a desktop: XFCE, `player` signed in by LightDM, no screen lock.

## The contract with the launcher

- The account is `player` (`ARG PLAYER=player`), with a home, passwordless sudo and a password of
  the box's own; the launcher opens its shell as that account. `smoke-test.sh` checks it.
- The launcher pins this repository's output: the image by its digest, and these files as they
  were at the commit that published it. A publish opens a pull request into the launcher's `dev`
  with both (`.github/workflows/image.yml`, its `pin` job).

## Building and testing

```sh
docker build --pull -t attack-box:local .
./smoke-test.sh attack-box:local
```

The workflow builds and smoke-tests every pull request on amd64 and arm64; a push to `main`, the
weekly run or a manual run publishes, only once both pass, then pulls the published digest and
smoke-tests it again before pinning it in the launcher.

It needs the Docker Hub organization's credentials (`DOCKER_ORGA`, `DOCKER_OAT`) and, for the pin,
`LAUNCHER_TOKEN`: a token that can push a branch to the launcher's repository and open a pull
request there.
