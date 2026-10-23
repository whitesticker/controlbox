# System Monitor top processes: what each list ranks

## Symptom

The detail submenus' **Top processes** lists did not match what people expect from Activity Monitor or iStat Menus:

- **Memory** ranked by RSS (`ps`), which counts shared pages in every process that maps them, so the numbers matched neither Activity Monitor's Memory column nor the system total.
- **Network** ranked by bytes since each process started (one `nettop` sample is cumulative), so a process that downloaded a lot an hour ago outranked one busy now. Each call also took about 5 s.
- **Battery** reused the CPU list as an "energy proxy".

## What each list ranks now

Every list shows five rows, refreshes every 2 s while its submenu is shown, and keeps its last result across opens.

| Section | Ranked by | Source |
|---|---|---|
| CPU | %CPU (kernel decaying average, per core) | setuid `/bin/ps -Aceo pid=,pcpu=,rss=,comm=` |
| Memory | Physical footprint (Activity Monitor's Memory) | long-lived setuid `top -o mem` |
| Battery | Energy Impact score (Activity Monitor's Energy) | long-lived setuid `top -o power` |
| Disk | Read + write bytes/s over the last 10 s, own-user processes only | libproc `proc_pid_rusage` |
| Network | In + out bytes/s over the last 4 s | one-shot `nettop -P -x -n -l 1`, two snapshots diffed |

Battery shows the Energy list on Macs without a battery too.

## Notes

- `top`'s first sample walks every process's memory map: ~0.75 s of system time. Later samples are ~0.12 s. So `TopStream` keeps one `top -l 0 -s 2` running per streamed list instead of spawning per refresh, and `TopProcessFeed` leaves it running 10 s after its submenu hides so sweeping across rows does not pay the first sample each pass. `top` flushes each sample to the pipe and dies on SIGPIPE if Control Box goes away. The first `power` sample is all zeros and is dropped; our own `top` processes are filtered out of the list.
- `top` and `nettop` cut names at 15–16 characters. `proc_name` gives the full name for own-user processes and fails for root ones, whose names are short anyway, so the tool's name is the fallback.
- `nettop` without `-n` resolves addresses and every call waits ~5 s. With `-n` a call is ~17 ms.
- `nettop` with more than one sample (`-l 2`, or `-d` delta mode) burns about a core per extra sample, through a pipe or a file. Diff one-shot snapshots instead.
- Network and Disk need two readings: the first refresh after an open takes a baseline, waits (1 s / 0.5 s), then ranks over that short window until the full window has filled.
- A process whose `nettop` total drops (sockets closed) counts as idle for that window.

## Do not

- Rank memory with `ps` RSS. Use `top`'s `mem` (footprint).
- Spawn `top` per refresh. Its first sample is the expensive one.
- Ask `nettop` for more than one sample, or call it without `-n`.
- Go back to cumulative network totals for "top processes".
