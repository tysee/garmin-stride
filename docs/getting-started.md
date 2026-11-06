# Set up your first Stride profile

[Documentation](README.md) · [Project home](../README.md)

## Build and initialize

Use macOS or Linux with Rust 1.99.1 and the platform's C/C++ linker toolchain
already installed. Use the pinned tools in `mise.toml` via mise; install missing
tools as a separate setup step. Building from source uses Cargo; running the resulting `stride`
binary needs neither Rust nor mise. If you already have a Stride binary, put its
directory on `PATH` and start with `stride --config /path/to/config.toml config init`.

```sh
git clone https://github.com/tysee/garmin-stride.git
cd garmin-stride
mise trust
mise exec -- cargo build --release --locked --bin stride
export PATH="$PWD/target/release:$PATH"
export GARMIN_STRIDE_CONFIG="$PWD/config.toml"
stride config init
stride init
stride status
```

`config init` writes `config.toml` unless it already exists. `init` creates the
database and applies migrations. Nothing else creates or migrates storage, so run
`init` again after updating.

## Connect Garmin

Behind a proxy or in a sandboxed agent environment, first run `stride doctor` from
the terminal that will run Stride. It checks HTTPS to Garmin without keys; see
[network path](configuration.md#network-path-proxies-and-trust-roots).

The guided setup covers profile preparation, credentials, Connect login, first
imports and optional HTTP access. Steps can be skipped or repeated. Opening it
changes nothing until you confirm a step.

```sh
stride setup
```

Each step shows a self-check: `√` when it is done, `×` when it needs attention,
with a one-line finding such as the activity count or the next key expiry. The
check reads only local files, never initializes missing storage and makes no
network requests.

Every command and the menu find the Personal API key the same way: an explicit
`--env-file`, otherwise `garmin.env` beside the profile database, otherwise the
`GARMIN_PERSONAL_API_KEY` environment variable. Once the key is saved, CLI commands
such as `stride garmin sync` need no `--env-file`. Without one, paste the key into
the hidden field. It shows only how many characters arrived, trims surrounding
spaces, checks the key with Garmin and saves it to a new `0600` `garmin.env`.
To replace a saved key, delete that file and open the step again. Profiles set
up by earlier versions kept `garmin.env` beside `config.toml`; move it into the
database directory or paste the key again.

<details>
<summary>Manual setup</summary>

Create a key in [Garmin Connect → Personal API](https://connect.garmin.com/app/settings/personalApiToken)
(see Garmin's [Personal API docs](https://developer.garmin.com/gc-developer-program/personal/swagger-docs/)).

```sh
cp -n .env.example .env
chmod 600 .env
```

Set `GARMIN_PERSONAL_API_KEY` in `.env`. Stride reads the file as data; never source
it, pass the key as an argument, commit it, or paste it into a chat.

```sh
stride --env-file .env garmin check
stride --env-file .env garmin sync --limit 20
stride garmin login
# Replace these example dates with the period you want to import.
stride --env-file .env health sync --start 2026-01-01 --end 2026-01-07
```

`garmin sync --start DATE [--end DATE]` imports every activity whose local start
date falls in the period (END defaults to today in UTC), reading
`history.max_page_size` activities per request and committing each page. The last
successful sync time moves only after the whole period is in. The menu's Sync
activities, and Onboarding's Import activities, ask whether to import recent
activities by count or a period; Esc stops a period before the next page.

`stride sync --start DATE [--end DATE]` imports activities, strength sets, health
and Coach for a period in one run and reports each step; see
[history and health](history-and-health.md). `garmin check` verifies access
without saving anything. Health sync covers at most
31 days per run and commits each day atomically; a failed day keeps its previous
data. The menu's Import health takes `START` or `START END` (END defaults to today
in UTC), splits longer ranges into 31-day parts after confirmation and shows
per-day progress. Esc stops after the current day; a stop or failure names the
date to continue from.

Garmin rate-limits request bursts (HTTP 429). Stride spaces requests to each Garmin
host by `garmin.request_interval_ms` (1 s by default), so a day of health takes
about 8 s. If Garmin still answers 429, reads wait as its `Retry-After` asks, at
most `rate_limit_max_wait_seconds` per wait and `rate_limit_retries` times, and
later requests in the same run are spaced twice as far apart (up to 8x). Writes
are never retried. The menu shows these waits; the CLI prints them as warnings.

</details>

## Read your data

```sh
stride activities list --limit 10
stride activities list --limit 10 --offset 10   # the next page
stride health show --date 2026-01-07
stride health list --start 2026-01-01 --end 2026-01-07
stride health samples --date 2026-01-07 --metric heart_rate --limit 100
```

The exports above apply to the current shell. In a new shell, put the executable's
directory on `PATH` and pass `--config /absolute/path/config.toml` or set
`GARMIN_STRIDE_CONFIG`. Relative storage paths resolve against that configuration file.

Next: [review your activity and health history](history-and-health.md),
[connect an assistant](assistant.md), or [inspect a Coach week](coach.md).
