# grntly-brewer ¯\\\_(ツ)_/¯

![Build passing](https://img.shields.io/badge/Build-pass-brightgreen)
![Platform](https://img.shields.io/badge/Platform-macOS-lightgrey)

Geharde, modulaire installer om nieuwe macOS-machines (Apple Silicon / M4) klaar
te zetten voor medewerkers van Grantly, Het Subsidie Lab, PWRSTAFF en Meetbaar —
plus een lichte agent om de vloot centraal te monitoren via Google Workspace.

## Snelstart

Kloon de repo en draai de installer (aanbevolen boven `curl | bash` i.v.m.
supply-chain-veiligheid):

```bash
git clone https://github.com/grntly/grntly_brewer.git
cd grntly_brewer
./install.sh            # interactieve setup (met bevestigingsscherm)
./install.sh --dry-run  # laat zien wat er zou gebeuren, wijzigt niets
./install.sh --yes      # sla het bevestigingsscherm over (onbemand)
./install.sh --rollback # accounts/naam/homebrew van een run terugdraaien
./install.sh --only 50,70   # alleen bepaalde modules draaien
```

Het **uitrolbeleid** staat in `config.d/policy.conf` (welke security-controls
worden afgedwongen en de standaard-antwoorden). De wizard toont vooraf één
samenvatting ter bevestiging, draait fouttolerant door, en sluit af met een
**eindcontrole** (exit 2 als een must-have niet goed staat).

## Wat de installer doet

De setup is opgesplitst in genummerde modules (`modules/NN-*.sh`), aangestuurd
door `install.sh` met gedeelde helpers in `lib/common.sh`:

| Module | Doel |
|--------|------|
| `00-preflight` | macOS/arch-checks + bedrijf/type/naam-keuzes |
| `10-accounts`  | veilige admin/gebruiker via `sysadminctl` (Secure Token, home dir) |
| `20-naming`    | computernaam `PREFIX-TYPE-JJNN-INIT` |
| `30-homebrew`  | Homebrew installeren/instellen (idempotent, geen onveilige perms) |
| `40-apps`      | app-profiel per rol/bedrijf uit `config.d/apps.tsv` + wallpaper + Dock |
| `50-security`  | FileVault, firewall, Gatekeeper, auto-updates, schermvergrendeling |
| `60-debloat`   | ongebruikte apps/rommel verwijderen (`config.d/bloat.tsv` + uninstallers) |
| `70-profiles`  | optimale macOS-defaults + beheerde `.bashrc` voor alle gebruikers |
| `80-developer` | **OrbStack** (docker + `orb`), VS Code-extensies, dev-Dock |

Configuratie zit als **data** in `config.d/` (bedrijven, apps, bloat) — geen
hardcoded lijsten meer.

## Centrale monitoring (Google Sheet)

Zonder MDM: elke Mac rapporteert inventory + Homebrew-updatestatus (gekoppeld
aan **serienummer + gebruiker**) naar één Google Sheet via een HMAC-gesigneerde
Apps Script Web App. Zie **[docs/ADMIN.md](docs/ADMIN.md)** voor de volledige
opzet. Installeren op een Mac:

```bash
sudo ./agent/install-agent.sh "<APPS_SCRIPT_EXEC_URL>" "<SHARED_SECRET>"
```

> **Grenzen:** live device-locatie en remote lock/wipe kunnen script-only niet
> betrouwbaar/privacy-compliant. Dat vereist MDM + Apple Business Manager. Deze
> agent is dan de bootstrap-laag onder een MDM.

## Losse tools

- `uninstallers/remove-*.sh` — specifieke uninstallers (Zoom, GarageBand).
- `app-uninstall.sh` — generieke app-uninstaller: `./app-uninstall.sh /Applications/X.app`.
- `gatekeeper_commander.sh` — Gatekeeper-status/quarantine helper (disable-optie is bewust verwijderd).
- `addprinters.sh` — voorbeeld printerconfiguratie.

## Ontwikkeling

`bash -n` + `shellcheck` draaien via GitHub Actions (`.github/workflows/shellcheck.yml`).
`install-poc.sh` en `mac_setup.sh` zijn legacy: `mac_setup.sh` is een shim naar
`install.sh`, `install-poc.sh` wordt niet meer onderhouden.
