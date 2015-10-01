# Auto Reaver Script

Launch reaver against all WPA/WPS discovered networks.

```bash
git clone https://github.com/eusonlito/auto-reaver.git
cd auto-reaver
chmod +x launch.sh
./launch.sh
```

Now, it will create `tmp` and `logs` folders.

* `tmp` will store packages to be installed.
* `logs` will store one file for each router mac.

## Requirements

* airmon-ng (from `aircrack-ng` package)
* wash (from `reaver` package)
* reaver (from `reaver` package)
