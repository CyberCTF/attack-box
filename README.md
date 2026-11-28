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
2. `vm/toolset.sh`: nothing where the box has Kali's toolset (Kali's own box, amd64); elsewhere (a
   Debian VM made Kali, on Arm) a small set, the same for every lab: Kali's core and the common web,
   network and password tools. The player installs more with `sudo apt install`.
3. The player's account: `player-account.sh`, run by the launcher with the box's shared folder and
   password file.
4. `vm/desktop.sh`, for a box with a desktop: XFCE, `player` signed in by LightDM, no screen lock.

## The contract with the launcher

- The account is `player` (`ARG PLAYER=player`), with a home, passwordless sudo and a password of
  the box's own; the launcher opens its shell as that account. `smoke-test.sh` checks it.
- The launcher pins this repository's output in its `src-tauri/attack-box.json`: the image by its
  digest, the commit that published it, and each script's SHA-256 there. It keeps no copy of the
  scripts: it downloads them at that commit and refuses one whose hash differs. A publish opens a
  pull request into the launcher's `dev` with the new pin (`.github/workflows/image.yml`, its `pin`
  job).
- The scripts' behaviour is tested here (`tests/scripts.sh`, run by `./check.sh`); the launcher
  tests only how it puts them together.

## Building and testing

```sh
./check.sh            # the scripts: the VM set-up's compositions parse, shellcheck
./check.sh image      # the image built locally and smoke-tested
./check.sh all        # both
```

The workflow runs the same command: it checks the scripts, and builds and smoke-tests every pull request on amd64 and arm64; a push to `main`, the
weekly run or a manual run publishes, only once both pass, then pulls the published digest and
smoke-tests it again before pinning it in the launcher.

It needs the Docker Hub organization's credentials (`DOCKER_ORGA`, `DOCKER_OAT`) and, for the pin,
`LAUNCHER_TOKEN`: a token that can push a branch to the launcher's repository and open a pull
request there.

## Verify the image

Each architecture's image carries BuildKit's SLSA provenance of its build, and the published
multi-arch index a build provenance attestation signed through Sigstore and kept by GitHub. There
is no SBOM attestation: Kali's toolset makes one larger than BuildKit accepts. With the digest the
launcher pins:

```sh
PINNED=cyberctf/attack-box@sha256:...
docker buildx imagetools inspect "$PINNED" --format '{{ json .Provenance }}'   # BuildKit's provenance
gh attestation verify "oci://index.docker.io/$PINNED" --repo CyberCTF/attack-box \
  --signer-workflow CyberCTF/attack-box/.github/workflows/image.yml           # built by image.yml here
```
