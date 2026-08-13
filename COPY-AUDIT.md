# Copy audit — the design as drawn, against what the code actually does

**Date: 13 August 2026.** Source: `WebShield Site.dc.html` in the Claude Design project
*WebShield Family Safety Redesign*.

The design was written from the product's intent. This is the pass that held every claim
in it against the running code, and it found **eleven** places where the site promised
something the system does not do, or did not do yet. Two of them were tier contents
listed **backwards**.

Every "reality" below was read from the deployed system rather than from a document:
`limitsForTier` and the settings tier table out of the running container image, the app's
`Features.kt`, `MainScreens.kt` and `build.gradle`, and `PROJECT.md` §14/§16/§19 for the
decisions behind them.

---

## The two that would have sold the wrong plan

### 1. Secure browsing and service blocking were swapped

The design put *"Secure browsing — scam & malware shield"* under **Premium** and *"Pause
social media & game apps"* under **Advanced**. The server says the opposite:

```
$ docker run --rm --entrypoint sh adguard-api-service:latest \
    -c 'grep -n "ADVANCED\|PREMIUM" dist/accounts/settings.js'
17:    secureBrowsing: 'ADVANCED',
18:    parentalControls: 'ADVANCED',
19:    safeSearch: 'ADVANCED',
20:    blockedServices: 'PREMIUM',
21:    allowedHours: 'PREMIUM',
```

This is the worst kind of error on a pricing page, because both directions cost real
money: an Advanced subscriber who bought it to switch TikTok off finds the picker locked
and asks for a refund, and a Premium subscriber paid a tier up for scam blocking they had
already. **Fixed** — the plan cards now mirror the server, with a comment above them
naming the file to change first.

### 2. "Pause social media & games at homework time" is the one shape the server cannot express

The design promised homework blocks in two places (the kids card and the Premium plan's
*"Bedtime & homework schedules"*). `PROJECT.md` §16 records what probing the live server
found: AdGuard owns the scheduler, the field is a **pause** window, and **a day holds
exactly one**. So it can say *"these services are available 07:00–21:00"* and it
**cannot** say *"blocked during homework, 15:00–17:00"* — the complement of one range is
two ranges.

The app already learned this. `Features.kt` renamed the feature to **Allowed hours** and
carries the explanation in a comment. The site was still selling the old promise.

**Fixed** — the site now says allowed hours everywhere, and an FAQ entry answers the
question a parent will actually ask ("Can I block apps during homework time?") by
explaining the inversion rather than dodging it.

---

## Claims about data that were more generous than the truth

### 3. The phone mockup advertised a "Blocked" count

The design's hero showed three tiles: `1,204 Checked`, `6h 12m Protected`, `188 Blocked`.

`blocked` **does not exist**. Per `PROJECT.md` §14, AdGuard tracks queries per client but
not blocks; the API returns `blocked_available: false` and the app deliberately shows
*"WebShield has protected N lookups"* instead. §14's own words: *"Sending 0 would read as
'nothing was blocked', which for an ad blocker is the most damaging possible lie."* A
marketing page showing 188 is that lie with a nicer font. `6h 12m Protected` was not a
metric the app has at all.

**Fixed** — two tiles, both of which the app can produce: lookups protected, and days of
history. A caption under the phone says it is an illustration and repeats the privacy
line, so the mockup now argues *for* the product rather than overstating it.

### 4. The FAQ said addresses are stored to build your statistics

Design: *"Those addresses are used to apply your rules and show you your own
statistics."*

That is two different retention stories in one sentence, and the second is wrong. Per
§2.3 and §14: the query log is a **1,000-entry in-memory ring, never written to disk** —
about three minutes for an active household — and the statistics are **counts with no
domain attached**. Addresses are used to apply rules and are then gone; they are not what
the chart is built from.

This matters beyond pedantry: it is the exact claim a Play reviewer or a regulator would
check against the data-safety form, and the form says counts.

**Fixed** — the answer now separates "passes through and is not written down" from "what
we keep is counts", in that order.

---

## Claims that were true but sold to the wrong audience

### 5–7. Advanced-tier features presented as though everyone gets them

The two pillar cards listed capabilities with no indication of which plan carries them, so
the page implied Basic includes parental controls, Safe Search and scam blocking. All
three are **Advanced**. Basic is `blockAds` and nothing else — `PROJECT.md` §12 records
that on BASIC the server's `allowed` list is exactly `["blockAds"]`, which is why four of
the five switches grey out.

**Fixed** — small `Advanced` / `Premium` badges on the affected lines. Cheaper than
rewriting the cards and it makes the plans table do its job.

---

## Claims about a future that has not shipped

### 8. Billing described in the present tense

*"Billed securely through Google Play — cancel anytime"* and *"Everything runs through
your Google Play account"*. Play Billing is item **2.1** and is **not built**; there is no
listing to buy from. **Fixed** — future tense, and the whole page is in coming-soon mode
with an early-access form rather than a dead Play badge.

### 9. The Play URL named an application ID we do not use

The design defaulted to `online.webshield.app`. `app/build.gradle:16` says
`applicationId "com.webshield.dnsvpn"`. A launched badge would have gone to a 404.
**Fixed** — no store link at all until the listing exists, and the correct id recorded in
`README.md` for when it does.

### 10. The "Notify me" box did nothing

In the design it set a flag in component state. Shipping that would mean collecting
addresses into a variable and discarding them on the next page load, while telling people
they were on a list. **Fixed** — it posts to `POST /api/v1/notify` on the account service,
which is new work in `adguard-api-service` (branch `feat/notify-signups`), and the page
reports a failure honestly instead of claiming success.

---

## One the design got slightly too absolute

### 11. "Blocked requests simply never arrive — no scary pages, no pop-ups"

True for ads and trackers, which are answered with nothing. Not true for the parental and
safe-browsing categories: `PROJECT.md` §3.8 records that `AdGuardHome.yaml` sets
`parental_block_host` and `safebrowsing_block_host`, so a blocked adult site currently
shows *"Access blocked by AdGuard DNS"*. **Fixed** — the note now distinguishes the two,
which also avoids a parent concluding the filter is broken when they see a block page.

---

## Checked and left alone

Worth recording, so the next pass does not re-litigate them:

| Claim | Verified against |
| --- | --- |
| 2 / 5 / 10 profiles, 5 / 15 / 30 devices | `limitsForTier` in the deployed image; matches `Features.profileLimitOf` |
| R29 / R39 / R49 and R299 / R399 / R499 | `PROJECT.md` §8. **R299 is deliberate charm pricing, not a rounding slip** |
| "Android 6.0 and up" | `minSdk 23` |
| "Safe Search enforced on every search engine" | True since the §13 fix, which moves every engine boolean including ones AdGuard adds later |
| Guardian PIN stops casual switching-off | §17 P5 — server-verified, rate-limited per device |
| "It's guidance, not a padlock" | §8, a settled decision, and the honest framing the whole product leans on |
| "Doesn't reroute your traffic or change your location" | §2.4 — the tunnel adds single-host `/32` and `/128` routes only |
| "Covers every app, not just the browser" | It is a device-wide VPN-based resolver |
| A profile for each child | §17 — per-profile handles and provisioning are built |
| "We count queries, never the sites you visit" | `strings.xml`, changed for this reason in §2.3 |

---

## Two things the port added that the design did not have

- **It is responsive.** The source was a fixed 1100px desktop canvas. A family-safety
  product is read on a phone, and a 1100px minimum meant sideways scrolling for most of
  the people we are talking to.
- **The typeface is self-hosted.** The design pulled Plus Jakarta Sans from
  `fonts.gstatic.com`, which hands every visitor's IP address to a third party on the page
  where we promise not to do that. 49KB of woff2 is a cheap way to mean it.

## One thing that could not be brought across

`father_son_169_banner_saftey-msq60h0s-539x.png` **cannot be fetched** — the design MCP's
`get_file` caps at 256 KiB and returns a truncated PNG (11% of the image decodes). This is
the known limitation in project memory. The photo band is currently a 16:9 crop of the
father-and-son source, which is the same subject the banner's filename names, so it reads
correctly — but it is the same photograph as the "For your kids" card, at a different crop.
**Swapping in the real banner is one file:** drop it at `assets-src/family-banner.png`, add
it to `TARGETS` in `tools/build-images.py`, and re-run.
