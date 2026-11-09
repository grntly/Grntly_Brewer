# Bedrijfswallpapers

De installer gebruikt per bedrijf een achtergrond uit deze map:

```
assets/wallpapers/<PREFIX>-macwallpaper.jpg
```

waarbij `<PREFIX>` de kolom `prefix` uit `config.d/companies.tsv` is
(`GRANTLY`, `HSL`, `PWRS`, `MTBR`).

## Voorrang

1. **Lokale asset** in deze map (aanbevolen — geen afhankelijkheid van een externe host).
2. Pas als die ontbreekt: de `wallpaper_url` uit `config.d/companies.tsv`.

## De echte artwork plaatsen

De meegeleverde bestanden zijn **placeholders** (donkere achtergrond + bedrijfsnaam).
Vervang ze door de echte merk-artwork met dezelfde bestandsnaam, bijvoorbeeld:

```
assets/wallpapers/HSL-macwallpaper.jpg   # echte HSL-wallpaper
assets/wallpapers/GRANTLY-macwallpaper.jpg
```

Aanbevolen: JPG of PNG, minimaal 2880×1800 (Retina). De bestandsnaam moet
`.jpg` blijven; macOS leest het bestandstype op inhoud, dus een PNG onder een
`.jpg`-naam werkt ook.
