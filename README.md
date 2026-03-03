# Cosmos Media Sync
Sync media downloads from a remote seedbox to a local media server using rsync, with per-app support for Radarr and Sonarr.

## Sync Script (sync.sh)
* Pulls new, unmarked items from the seedbox
* Writes daily logs per app
* Creates marker files on seedbox after successful sync
* Uses per-app lock to prevent overlapping cron job runs

## Cleanup Script (downloads-cleanup.sh)
* Connects to seedbox and finds marked items
* Deletes matching local folders/files that have already been synced (those that are marked)
* Writes daily logs per app
* Uses per-app lock to prevent overlapping cron job runs

## Requirements
* Bash 4+
* `rsync`
* `ssh`
* SSH key authentication configured
* `flock`
* `python3`

## Configuration
Create config/.env with the following variables:
```
SEEDBOX_HOST="user@seedbox-ip"
REMOTE_BASE="/home/user/downloads/rtorrent"
LOCAL_BASE="/mnt/media"
MOVIES_DEST="movies"
SHOWS_DEST="shows"
KEY="/home/localuser/.ssh/id_ed25519"
MARKER=".synced_to_<local_media_server>"
```

### Variables
| Name         | Description                              |
|--------------|------------------------------------------|
| SEEDBOX_HOST | SSH user + host IP of the seedbox        |
| REMOTE_BASE  | Root folder on seedbox                   |
| LOCAL_BASE   | Base media folder on local media server  |
| MOVIES_DEST  | Movies folder on local media server      |
| SHOWS_DEST   | TV Shows folder on local media server    |
| KEY          | SSH private key path                     |
| MARKER       | Marker file name used to prevent re-sync |

### Local Destination Mapping
The script maps apps to local folders:
| App          | Local Destination                        |
|--------------|------------------------------------------|
| Radarr       | $LOCAL_BASE/$MOVIES_DEST                 |
| Sonarr       | $LOCAL_BASE/$SHOWS_DEST                  |

## How It Works
### Re-Sync Prevention
After a successful transfer directories and files get a marker file.

* **Directories**: `<dir>/$MARKER` (example: `Some.Movie.2026/.synced_to_media_server`)
* **Files**: `<filename>.$MARKER` (example: `SnarkyDocumentary.mp4.synced_to_media_server`)

On future runs, anything with a marker is skipped.

### Local Cleanup
Connects to the seedbox and finds items that have marker files. If the file/folder exists locally, it deletes it. This allows for automated cleanup of completed downloads. Ideally run once a day to allow Radarr/Sonarr time to process it.

### Logging
Daily logs are stored in `./logs` and deleted automatically after 14 days.

**Example log line:**

`2026-03-02 04:52:01 [sync.sh/radarr] Syncing new items to /mnt/media/movies...`

### Concurrency
The script uses `flock` and a per-app lock file in `./locks` to prevent overlapping runs. If a run is already in progress and cron triggers another one, the new run will log a message and exit cleanly.

## Setup
1. Clone the repository on the media server
2. Setup config/.env as shown above
3. Make the script executable: `chmod +x scripts/sync.sh`

## Usage
### Sync
#### Manual Run
```
./scripts/sync.sh radarr
./scripts/sync.sh sonarr
```

#### Example Cron Job
Run Radarr sync every 10 minutes:
```
0 * * * * /home/user/repos/cosmos-media-sync/scripts/sync.sh radarr
```
Run Sonarr sync every 10 minutes:
```
0 * * * * /home/user/repos/cosmos-media-sync/scripts/sync.sh sonarr
```

### Cleanup
#### Manual Run
The Dry Run tag is Safe Mode.
```
./scripts/downloads-cleanup.sh radarr --dry-run
./scripts/downloads-cleanup.sh sonarr --dry-run
./scripts/downloads-cleanup.sh radarr --delete
./scripts/downloads-cleanup.sh sonarr --delete
```

#### Example Cron Job
Cleanup daily at 2 AM
```
0 2 * * * /home/user/repos/cosmos-media-sync/scripts/downloads-cleanup.sh radarr --delete
20 2 * * * /home/user/repos/cosmos-media-sync/scripts/downloads-cleanup.sh sonarr --delete
```
