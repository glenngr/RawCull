# Git-arbeidsflyt: Lineær historikk (ingen merge commits)

Denne guiden beskriver din faste arbeidsflyt for utvikling i branches, bruk av Claude for automatiske commit-meldinger, og integrasjon mot main uten merge-commits.

## Arbeid på branchen din — stage og commit

Du jobber alltid på en dedikert branch. Når du skal lagre endringer, bruker du Claude til å generere en "Conventional Commit"-melding basert på endringene dine.

### 1. Stage alle endringer
```bash
git add .
```

### 2. Commit med melding generert av Claude

Dette bruker aliaset ditt for å skrive meldingen automatisk

```bash
git commit -m "$(git diff --staged | claude -p 'Write a short conventional commit message. Output only the message, nothing else.')"
```
Gjenta disse stegene så ofte som nødvendig mens du arbeider.

### 3. Skyv branchen til GitHub

For å dele koden eller ha en sikkerhetskopi i skyen.

```bash
git push origin <din-branch>
```


### 4. Hent siste oppdateringer (uten merge commits)

Hvis det er gjort endringer på GitHub som du ikke har lokalt, bruk rebase for å legge dine commits på toppen av de nye endringene.

```bash
git pull --rebase origin <din-branch>
```

## 5. Fullfør arbeidet — merge til main (Fast-Forward)

Når funksjonaliteten i branchen er ferdig og skal inn i main, følger vi denne prosedyren for å sikre at historikken forblir en rett linje.

### 1. Gå til main og hent det aller nyeste fra serveren

```bash
git checkout main
git pull --rebase origin main
```
### 2. Gå tilbake til branchen din og rebase den på toppen av den ferske main-branchen
```bash
git checkout <din-branch>
git rebase main
```

### 3. Gå tilbake til main og utfør en "fast-forward" merge

`--ff-only` sikrer at Git aldri lager en merge-commit

```bash
git checkout main
git merge --ff-only <din-branch>
```

### 4. Push den oppdaterte main-branchen til GitHub

```bash
git push origin main
```

### 5. Opprydding — slett branchen

Når endringene dine er trygt pushet til main, kan du slette arbeidsbranchen både lokalt og på GitHub.

### 6. Slett lokalt
```bash
git branch -d <din-branch>
```

### 7. Slett på GitHub (remote)
```bash
git push origin --delete <din-branch>
```
## Anbefalte Git-instillinger for din flyt

For å være helt sikker på at du aldri lager en merge-commit ved et uhell (f.eks. ved en pull), kan du sette disse innstillingene globalt:

### 1. Bruk alltid rebase i stedet for merge ved pull
```bash
git config --global pull.rebase true
```
### 2. Tillat kun fast-forward merges (nekter merge-commits)

```bash
git config --global merge.ff only
```

## Signering

### 1. Signer den siste commiten på nytt uten å endre meldingen
```bash
git commit --amend --no-edit -S
```

###  2. Push på nytt (du må bruke --force-with-lease siden commit-hashen endret seg)

```bash
git push origin version-1.5.9 --force-with-lease
```

### Engangsoppsett for GPG & SSH

For at signering skal skje automatisk med din GPG-nøkkel, kjør disse kommandoene for krav om 100 % signert (GPG), lineær historikk over SSH.

```bash
# 1. Finn din GPG Key ID (det er den 8 eller 16-tegns koden etter '/' på 'sec' linjen)
gpg --list-secret-keys --keyid-format LONG

# 2. Fortell Git hvilken nøkkel som skal brukes
git config --global user.signingkey <DIN_KEY_ID>

# 3. Aktiver automatisk signering og spesifiser GPG-programmet
git config --global commit.gpgsign true
git config --global gpg.program gpg

# 4. Sikre lineær historikk (ingen merge-commits)
git config --global pull.rebase true
git config --global merge.ff only
```

## Fikse GPG

```bash
git config --global gpg.format openpgp

# Sørg for at Git bruker riktig program
git config --global gpg.program gpg

# Sørg for at Key ID er riktig (uten '0x' foran)
git config --global user.signingkey <DIN_KEY_ID>
```

## Ny branch med lineær historikk

For å unngå merge commits og holde historikken lineær (slik reglene i repoet ditt krever), bør du gå over til en rebase-basert arbeidsflyt. Her er den faste rutinen du bør følge:

### 1. Start alltid fra en oppdatert main

Før du lager en ny branch, må du sørge for at utgangspunktet ditt er ferskt.

```bash
git checkout main
git pull origin main
```

### 2. Opprett ny branch

```bash
git checkout -b feature-navn
```

### 3. Gjør arbeidet ditt (Commit ofte)

Gjør endringene dine i koden og commit dem lokalt.

```bash
git add .
git commit -m "Beskrivelse av endring"
```

### 4. Hent oppdateringer fra andre (Viktigst!)

Hvis andre har pushet ting til main mens du jobbet, må du flytte dine commits til toppen av deres arbeid. I stedet for git merge, bruker du:

```bash
git fetch origin
git rebase origin/main
```

Dette tar dine nye commits, legger dem til side, oppdaterer branchen din med det nyeste fra main, og legger dine commits på toppen igjen.

### 5. Push til GitHub

Nå kan du pushe branchen din. Siden historikken er en rett linje uten merge commits, vil GitHub godta den.

```bash
git push -u origin feature-navn
```