# webshield-site

The marketing site for **WebShield** — `https://webshield.online`.

Four static files and some pictures. No build step, no framework, no npm. That is
deliberate: the whole site is one page and a policy, and anything that needed a toolchain
to change a price would be the tail wagging the dog.

---

## What this replaced, and what it did not

The site used to be WordPress 6.8 + Astra + Elementor + WooCommerce (2 GB of it, with
Jetpack, Wordfence, SpeedyCache and a PayFast gateway). **That WordPress is still running.**

nginx now serves this static site at the root and falls through to WordPress for anything
it does not have:

```
/            -> public/index.html
/privacy     -> public/privacy.html
/assets/...  -> public/assets/...
everything else -> WordPress, exactly as before
```

So the blog, the store, `/wp-admin` and every plugin endpoint still work, and nothing had
to be enumerated to keep them working. See the comments in
[`deploy/webshield.online.conf`](deploy/webshield.online.conf) for the reasoning and the
rollback, which is one location block.

**Backup taken before the first deploy** — files, database, both nginx vhost sets, with
checksums:

```
/opt/backups/wordpress-20260813-140254/
  wordpress-www.tar.gz      1.6G
  wordpress-db.sql.gz       4.5M
  wordpress-config.tar.gz
  nginx-host-vhosts.tar.gz
  SHA256SUMS                (verified)
```

---

## Layout

```
public/                 everything served, and nothing else
  index.html            the page
  privacy.html          the policy — reachable, deliberately not linked yet
  assets/css/site.css   one stylesheet, tokens at the top
  assets/js/site.js     nav, price toggle, signup form. No dependencies
  assets/fonts/         Plus Jakarta Sans, self-hosted on purpose
  assets/img/           generated — do not edit by hand
assets-src/             the full-resolution originals
tools/build-images.py   assets-src/ -> public/assets/img/
deploy/                 nginx vhost and the deploy script
COPY-AUDIT.md           every claim on the page, against what the code does
```

### Rebuilding the images

```bash
python tools/build-images.py
```

6.3 MB of source PNG becomes 303 KB of WebP plus JPEG fallbacks. Re-run it after changing
anything in `assets-src/`.

---

## Deploying

```bash
./deploy/deploy.sh            # upload public/ only
./deploy/deploy.sh --nginx    # also install the vhost and reload
```

Needs the SSH key at `~/.ssh/ws.pem` with mode 600 (copy it from
`C:\dev\Webshield Cert\PKI\Webshield_Online_PK.pem` first — OpenSSH rejects the original's
permissions) and the `jeremyl` account, which has passwordless sudo. `nginx -t` is the
gate before any reload, so a bad config is never served.

---

## Two things to know before editing the copy

**1. The plan cards mirror the server, and the server wins.**

```
blockAds .......... BASIC
secureBrowsing .... ADVANCED
parentalControls .. ADVANCED
safeSearch ........ ADVANCED
blockedServices ... PREMIUM
allowedHours ...... PREMIUM
profiles/devices .. 2/5, 5/15, 10/30
```

Read from the deployed image, not from a document. The design had two of these backwards
— see [COPY-AUDIT.md](COPY-AUDIT.md). If you change a plan here, change it in
`adguard-api-service` first.

**2. It is a schedule of *allowed* hours, not a blocking window.**

AdGuard's scheduler is a pause window and a day holds exactly one, so *"available
07:00–21:00"* can be expressed and *"blocked 15:00–17:00"* cannot. Do not let "homework
blocks" back into the copy. `PROJECT.md` §16 has the probe that established this.

---

## The launch switch

The site is in **coming soon** mode: there is no Play listing yet and Play Billing is not
built (`PROJECT.md` item 2.1), so the call to action is an early-access email box rather
than a store badge that would 404.

To go live, in `public/index.html`:

1. Hero badge → *"Now on Google Play"*, hero CTA → *"Get WebShield free"*.
2. Replace the `.notify-form` and `.download-aside` with the real Play badge, linking to
   `https://play.google.com/store/apps/details?id=com.webshield.dnsvpn`.
   **That application id is `com.webshield.dnsvpn`** (`app/build.gradle:16`) — the design
   source had `online.webshield.app`, which does not exist.
3. Plan CTAs → *"Start free trial"*.
4. Billing copy back to present tense ("Billed securely through Google Play").

The comment block above the `#download` section says the same thing in place.

## The privacy policy

`/privacy` is live and **`noindex`**, and the footer does not link to it yet. It still
carries `[LEGAL ENTITY NAME]`, `[registration number]` and `[address]`, and has not been
seen by a lawyer. When it has:

1. Fill in the bracketed details.
2. Remove the `robots` meta tag from `public/privacy.html`.
3. Turn the footer's plain-text *"Privacy Policy"* into a link, in both files.

Do all three together. The source of truth for the wording is
`webshield_android/docs/privacy-policy.md`; this page adds §2.6, the early-access list,
which the app-only policy had no reason to cover.
