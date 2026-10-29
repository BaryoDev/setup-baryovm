# setup-baryovm

Installs a pinned, checksum-verified [BaryoVM](https://github.com/BaryoDev/BaryoVM) release in a GitHub Actions job.

```yaml
- uses: BaryoDev/setup-baryovm@v1
  with:
    version: 0.5.0
- run: baryovm version
```

## Inputs

| Name | Required | Default | Meaning |
| --- | --- | --- | --- |
| `version` | yes | | Version to install, for example `0.5.0`. A leading `v` is accepted. |
| `allow-latest` | no | `false` | `version: latest` is refused unless this is `true`. Then the newest release is looked up through the GitHub API. |
| `github-token` | no | `github.token` | Used only for the API lookup and to avoid rate limits on downloads. |

## Outputs

| Name | Meaning |
| --- | --- |
| `version` | The version that was installed. |
| `path` | Directory that holds the `baryovm` binary. |

## What it does

1. Picks the archive for the runner: Linux or macOS, X64 or ARM64.
2. Downloads `checksums.txt` from the release on every run, and the archive unless it is cached.
3. Checks the SHA-256 of the archive (cached or fresh) against `checksums.txt` and fails the step on a mismatch or a missing line, before anything is extracted.
4. Extracts a fresh binary to a versioned directory under `runner.tool_cache` and adds it to `PATH`.
5. Sets `BARYOVM_HOME` to a directory under `RUNNER_TEMP`, so state stays out of the workspace.
6. Caches the archive, never the binary, with `actions/cache`, keyed by version, OS and architecture. A cache hit skips the archive download, not the check.

The checksum file comes from the same release as the archive, so it proves the download is intact, not who published it. Downloads are https only, redirects included.

The action is composite shell, with nothing to build. Inputs reach the script as environment variables, never interpolated into the script text.

## What it does not do

No SSH key handling and no release. It installs the tool and stops, so the job's own steps stay visible.

## Running BaryoVM from CI

Running BaryoVM from CI is only safe once host keys are verified. BaryoVM #12 added host key verification and shipped before 0.5.0, so pin 0.5.0 or later. The guide for running BaryoVM from CI (keys, known_hosts, secrets) is BaryoVM #85, which is still open. Read it before you give a job a key to a real host.

## Tests

`.github/workflows/test.yml` installs 0.5.0 on `ubuntu-latest`, `ubuntu-24.04-arm` and `macos-latest` and checks `baryovm version`. Two more jobs check that `latest` is refused and that an archive that does not match `checksums.txt` fails the step. The tamper job points the script at a local `file://` release through `BARYOVM_DOWNLOAD_BASE`, which exists for tests only.

## License

MPL-2.0.
