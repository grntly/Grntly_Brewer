# Grntly Brewer — Admin runbook

Centraal beheer van de macOS-vloot **zonder MDM**: elke Mac rapporteert zijn
inventory + Homebrew-updatestatus naar één Google Sheet, en updates worden
periodiek beheerd via Homebrew.

## Architectuur

```
 Mac (report.sh, LaunchDaemon elke 4u)
    │  HMAC-SHA256 gesigneerde HTTPS POST (sig=... query param)
    ▼
 Google Apps Script Web App (backend/AppsScript.gs)
    │  verifieert signature, upsert op serienummer
    ▼
 Google Sheet "devices"  ← admin leest/beheert hier
```

## 1. Google Sheet + Apps Script opzetten

1. Maak een nieuwe Google Sheet aan in de Workspace (bv. "Mac Fleet Inventory").
   Noteer de **Sheet ID** uit de URL (`/d/<SHEET_ID>/edit`).
2. **Extensies → Apps Script**. Plak de inhoud van `backend/AppsScript.gs`.
3. **Projectinstellingen → Scripteigenschappen** — voeg toe:
   - `SHEET_ID` = de sheet-ID
   - `SHARED_SECRET` = een lange, willekeurige string
     (`openssl rand -hex 32`). **Dit is het gedeelde geheim.**
4. **Deploy → Nieuwe implementatie → type "Web-app"**:
   - *Uitvoeren als*: Ikzelf
   - *Toegang*: Iedereen  ← veilig, want authenticatie gebeurt via de HMAC-signature
5. Kopieer de `/exec`-URL. Dit is `GRNTLY_ENDPOINT`.

> **Waarom "Iedereen" veilig is:** zonder `SHARED_SECRET` kan niemand een geldige
> signature maken; ongesigneerde/foute requests krijgen HTTP 401.

## 2. Agent op een Mac installeren

```bash
sudo ./agent/install-agent.sh "<EXEC_URL>" "<SHARED_SECRET>"
```

Dit schrijft `/etc/grntly/agent.conf` (root, 600), plaatst de scripts in
`/usr/local/grntly/` en laadt twee LaunchDaemons:

| Daemon | Doel | Schema |
|--------|------|--------|
| `com.grntly.report`  | inventory + brew-status rapporteren | elke 4 uur + bij load |
| `com.grntly.upgrade` | `brew update/upgrade/cleanup`       | wekelijks (ma 09:00) |

Handmatig testen: `sudo /usr/local/grntly/report.sh`

## 3. Wat de admin ziet (Sheet-kolommen)

`serial, hostname, user, model, os_version, os_build, filevault, firewall,
gatekeeper, free_gb, uptime, brew_outdated_count, brew_outdated, reported_at`

- **Update-status** = `brew_outdated_count` / `brew_outdated` per **serienummer + user**.
- **Compliance** = `filevault` / `firewall` / `gatekeeper` (allemaal `on` = goed).
- Eén rij per serienummer (upsert), dus altijd de laatste stand.

## 4. Secret roteren

1. Zet een nieuw `SHARED_SECRET` in Scripteigenschappen.
2. Werk `/etc/grntly/agent.conf` op elke Mac bij (of her-installeer de agent).
   Tip: rol dit uit via je bestaande onboarding-run.

## 5. Bekende grenzen (script-only)

- **Live locatie van devices** en **remote lock/wipe** kunnen hiermee *niet*.
  Dat vereist MDM + Apple Business Manager (Kandji/Mosyle/Jamf). Als dit een
  harde eis wordt, is de agent hierboven de bootstrap-laag onder een MDM.
- De agent draait als root-daemon; `brew`-acties worden als de console-gebruiker
  uitgevoerd omdat Homebrew user-owned is.

---

# Remote beheer (Tailscale + SSH)

Doel: vanaf je MacBook veilig bij elke bedrijfslaptop komen — waar hij ook staat,
achter NAT — om updates te draaien. Geen rauwe internet-SSH; Tailscale
(WireGuard) regelt bereikbaarheid en toegangscontrole.

## 1. Eenmalig instellen (Tailscale admin)

1. Maak een **tag** `tag:grntly-macs` en een **auth key** met die tag
   (Settings → Keys → Generate auth key; "Reusable" aan, evt. "Ephemeral" uit).
2. Zet een **ACL** die alleen admins bij de Macs laat (voorbeeld):

```jsonc
{
  "tagOwners": { "tag:grntly-macs": ["autogroup:admin"] },
  "acls": [
    { "action": "accept", "src": ["autogroup:admin"], "dst": ["tag:grntly-macs:22"] }
  ],
  "ssh": [
    { "action": "accept", "src": ["autogroup:admin"],
      "dst": ["tag:grntly-macs"], "users": ["admin", "autogroup:nonroot"] }
  ]
}
```

3. Zet **jouw publieke SSH-sleutel** in `config.d/ssh_authorized_keys`
   (één per regel). Haal 'm op met `cat ~/.ssh/id_ed25519.pub`.

## 2. Bij het uitrollen (op de Mac)

Module `55-remote` doet automatisch:
- Remote Login (sshd) aan + gehard: **alleen sleutels**, geen wachtwoord, geen root.
- Jouw publieke sleutel in het admin-account.
- Tailscale installeren en aanmelden met de auth key (tag `grntly-macs`),
  hostnaam = computernaam (bv. `GRANTLY-MBP-2601-JD`).
- `grntly-update` commando geïnstalleerd.

De auth key geef je mee zonder dat hij in `ps`/history belandt:

```bash
TS_AUTHKEY='tskey-auth-xxxx' ./install.sh            # onbemand
# of je wordt er tijdens de wizard veilig naar gevraagd (niet zichtbaar).
```

## 3. Verbinden en updaten (vanaf je MacBook)

```bash
# lijst van laptops in je tailnet
tailscale status

# verbinden (hostnaam of tailnet-IP)
ssh admin@GRANTLY-MBP-2601-JD

# updates draaien op afstand (brew + macOS software-updates)
ssh admin@GRANTLY-MBP-2601-JD 'sudo /usr/local/grntly/grntly-update.sh'
# of, met Tailscale SSH:
tailscale ssh admin@GRANTLY-MBP-2601-JD sudo /usr/local/grntly/grntly-update.sh
```

Logboek op de Mac: `/var/log/grntly-update.log`. Na een update rapporteert de
machine zijn nieuwe status naar de Google Sheet (als de reporting-agent draait).

> `grntly-update.sh` herstart niet automatisch. Updates die een reboot vereisen
> worden gedownload/voorbereid; plan de reboot zelf of voeg `--restart` toe.
