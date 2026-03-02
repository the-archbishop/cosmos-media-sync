# Cosmos Media Sync
Sync media downloads from a remote seedbox to a local media server using rsync, with per-app support for Radarr and Sonarr.

## Requirements
* Bash 4+
* rsync
* SSH access to seedbox
* SSH key authentication configured

## Configuration
Create config/.env with the following variables:
```
SEEDBOX_HOST="user@seedbox-ip"
REMOTE_BASE="/home/user/downloads/rtorrent"
LOCAL_BASE="/mnt/media"
KEY="/home/localuser/.ssh/id_ed25519"
MARKER=".synced_to_<local_media_server>"
```

### Variables
| Name         | Description                              |
|--------------|------------------------------------------|
| SEEDBOX_HOST | SSH user + host IP of the seedbox        |
| REMOTE_BASE  | Root folder on seedbox                   |
| LOCAL_BASE   | Base media folder on local media server  |
| KEY          | SSH private key path                     |
| MARKER       | Marker file name used to prevent re-sync |

### Local Destination Mapping
The script maps apps to local folders:
| App          | Local Destination                        |
|--------------|------------------------------------------|
| Radarr       | $LOCAL_BASE/films                        |
| Sonarr       | $LOCAL_BASE/shows                        |

## Re-Sync Prevention
After a successful transfer directories and files get a marker file.

* **Directories**: `<folder>/.synced_to_<local_media_server>`
* **Files**: `<filename>.synced_to_<local_media_server>`

On future runs, anything with a marker is skipped.

## Logging
Daily logs are stored in `./logs` and deleted automatically after 14 days.

**Example log line:**

`2026-03-02 04:52:01 [sync.sh/radarr] Syncing new items to /mnt/media/movies...`

## Example Cron Job
```
0 * * * * /home/user/repos/media-sync/scripts/sync.sh radarr
```
