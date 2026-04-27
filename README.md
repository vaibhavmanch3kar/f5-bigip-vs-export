# F5 BIG-IP Virtual Server Export Tool

> **Export all Virtual Servers, Pool Members, Health Status, and Configuration to Screen + CSV in one command.**

[![Platform](https://img.shields.io/badge/platform-F5%20BIG--IP-red?style=flat-square)](https://www.f5.com)
[![Shell](https://img.shields.io/badge/shell-bash-green?style=flat-square)](https://www.gnu.org/software/bash/)
[![Version](https://img.shields.io/badge/version-2.0-blue?style=flat-square)](CHANGELOG.md)
[![BIG-IP](https://img.shields.io/badge/BIG--IP-13.x%20%7C%2014.x%20%7C%2015.x%20%7C%2016.x-orange?style=flat-square)](https://support.f5.com)
[![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)](LICENSE)

---

## What It Does

A single bash script that runs directly on your F5 BIG-IP and produces:

- **Real-time screen output** — formatted table printed as each VS is processed
- **CSV file** — saved to `/var/tmp/` with timestamp, ready for Excel/reporting

### CSV Columns Exported

| Column | Description |
|---|---|
| `VS_Name` | Virtual server short name |
| `Partition` | BIG-IP partition (Common, etc.) |
| `Destination` | VIP IP:Port |
| `Protocol` | tcp / udp / any |
| `Admin_State` | enabled / disabled |
| `Availability` | available / offline / unknown |
| `Reason` | Human-readable status reason |
| `Default_Pool` | Associated pool full path |
| `LB_Method` | round-robin / least-connections / etc. |
| `Monitor` | Health monitor name(s) |
| `Total_Members` | Total pool member count |
| `Members_Up` | Members with availability = available |
| `Members_Down` | Members offline or unavailable |
| `Members_Enabled` | Admin-enabled members |
| `Members_Disabled` | Admin-disabled members |
| `Member_IPs` | Resolved IP:Port per member |

---

## Screen Output Preview

```
------------------------------------------------------------------------------------------------
No.  VS Name                        Destination            Pool           State       Avail       LB Method              Total   Up Down   En  Dis  Member IPs
------------------------------------------------------------------------------------------------
1    http-vs                        10.1.1.100:80          http-pool      enabled     available   round-robin                3    3    0    3    0  10.0.0.1:80  10.0.0.2:80  10.0.0.3:80
2    https-vs                       10.1.1.100:443         https-pool     enabled     available   least-connections-m        2    1    1    2    0  10.0.0.4:443  10.0.0.5:443
3    mgmt-vs                        10.1.1.200:8443        (no pool)      enabled     unknown                                0    0    0    0    0
4    legacy-app                     10.1.1.101:80          app-pool       disabled    offline     round-robin                2    0    2    0    2  10.0.0.6:8080  10.0.0.7:8080
------------------------------------------------------------------------------------------------
```

---

## Requirements

- F5 BIG-IP **13.x or later**
- Bash shell access (not tmsh shell) — login as `root` or switch to bash:
  ```bash
  bash   # from tmsh prompt, type 'bash'
  ```
- `tmsh` available in PATH (standard on all BIG-IP systems)
- No external dependencies — uses only standard Linux tools (`awk`, `grep`, `cut`, `sed`)

---

## Installation & Usage

### 1. Copy script to BIG-IP

**Option A — Direct paste:**
```bash
# SSH into BIG-IP, open bash, then:
vi /var/tmp/f5_vs_export.sh
# Paste script content, save with :wq!
```

**Option B — SCP (if admin shell is bash):**
```bash
scp f5_vs_export.sh root@<BIGIP-IP>:/var/tmp/
```

**Option C — Via curl (if BIG-IP has internet access):**
```bash
curl -o /var/tmp/f5_vs_export.sh \
  https://raw.githubusercontent.com/<your-username>/f5-bigip-vs-export/main/f5_vs_export.sh
```

### 2. Make executable
```bash
chmod +x /var/tmp/f5_vs_export.sh
```

### 3. Run
```bash
# Standard run (progress to stderr, table to stdout)
/var/tmp/f5_vs_export.sh

# Suppress progress messages — table output only
/var/tmp/f5_vs_export.sh 2>/dev/null

# Run in background (recommended for 100+ VS environments)
tmux new -s f5export
/var/tmp/f5_vs_export.sh

# Or with nohup:
nohup /var/tmp/f5_vs_export.sh > /var/tmp/f5_run.log 2>&1 &
tail -f /var/tmp/f5_run.log
```

### 4. Retrieve the CSV

**Option A — cat to terminal (copy-paste into Notepad → save as .csv):**
```bash
cat /var/tmp/f5_vs_*.csv
```

**Option B — REST API download (recommended, no SCP needed):**
```bash
# On BIG-IP:
cp /var/tmp/f5_vs_*.csv /var/config/rest/downloads/

# On your workstation:
curl -sku admin:PASSWORD \
  https://<BIGIP-IP>/mgmt/shared/file-transfer/downloads/f5_vs_<TIMESTAMP>.csv \
  -o f5_export.csv
```

**Option C — SCP (only works if admin shell is set to bash, not tmsh):**
```bash
scp root@<BIGIP-IP>:/var/tmp/f5_vs_*.csv ./
```

---

## Performance Notes

This script uses a **per-VS tmsh call loop** — the same proven approach as F5 KB article K72255145. On large environments:

| VS Count | Approx. Runtime |
|---|---|
| < 50 | 2–5 minutes |
| 50–150 | 5–15 minutes |
| 150–300 | 15–30 minutes |
| 300+ | Use `nohup` or `tmux` |

> **Always run inside `tmux` or `nohup` on production boxes** to prevent SSH/WinSCP timeout from killing the session mid-export.

---

## Troubleshooting

### Member IPs showing blank
The `address` field extraction uses `cut -d" " -f14` which requires **12 leading spaces** before the `address` keyword — standard on BIG-IP 14.x/15.x/16.x. If blank, check your indentation:
```bash
tmsh list ltm pool <poolname> | grep address | cat -A
# Count spaces before "address" — if not 12, adjust -f14 accordingly
```

### Pool shows `(pool not found)`
Pool key mismatch — usually a partition prefix issue. Check:
```bash
tmsh list ltm virtual <vs-name> | grep "^    pool"
# vs
tmsh list ltm pool recursive | grep "^ltm pool"
```

### WinSCP disconnects during run
See [Performance Notes](#performance-notes). Use `tmux` or `nohup`.

### Script exits immediately
Make sure you are in **bash**, not tmsh shell:
```bash
bash    # switch from tmsh to bash
```

---

## References

| Source | Link |
|---|---|
| F5 KB K72255145 | [How to export VS and Pools to CSV](https://my.f5.com/manage/s/article/K72255145) |
| F5 KB K000135606 | [How to export VS status to CSV](https://my.f5.com/manage/s/article/K000135606) |
| F5 DevCentral | [virtual_stats TMSH CLI Script](https://community.f5.com/t5/codeshare/tmsh-cli-script-virtual-server-state-status-pool-name-report-in/ta-p/288559) |

---

## Contributing

Pull requests welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

Common improvement areas:
- GTM/DNS WideIP export layer
- ASM/WAF policy association column
- iRule-to-VS mapping
- iControl REST API version (no tmsh dependency)

---

## License

MIT License — see [LICENSE](LICENSE).

---

## Author

Built for F5 BIG-IP network infrastructure auditing and documentation.
Tested on BIG-IP 14.x and 15.x with confirmed working `cut -d" " -f14` member IP extraction.
