# Names

SPEC.md calls "Lockin" a working name. These are candidates to check before launch. **None of them
has been checked yet**: App Store Connect only tells you a name is taken when you try to create
the app with it, and domains and social handles need a look on the day.

## What the name has to do

- Say "focus with friends" or "lock in" to a 15–22-year-old in one glance.
- Work as a verb in a sentence people already say: "lock in with me".
- Fit the App Store's 30-character name with a subtitle doing the explaining.
- Not lean on another focus app's mascot or name (CLAUDE.md, product rules).

## Candidates

| Name | Why | Worry |
|---|---|---|
| **Lockin** | The slang itself; the Lockling mascot is already a padlock | Likely crowded on the App Store and as a .com |
| **Lockin: Study with Friends** | Same name; the store name carries the category | Long; the home screen still shows "Lockin" |
| **Locked In** | Reads as a state, works on the Lock Screen ("Ava is locked in") | Common phrase, hard to own in search |
| **Lockling** | The mascot as the name; unique and ownable | Doesn't say "focus" without the subtitle |
| **Squadlock** | Says squad and lock | Sounds like a security product |
| **Lock Squad** | Clear, social | Two words; might read as a game |
| **Deskmates** | Leans into desk mode and studying together | Loses the "lock in" slang |

## Recommendation

Keep **Lockin** as the store name if "Lockin: Study with Friends" is free, with **Lockling** as
the fallback (and the mascot either way). Check in this order, and stop at the first that passes
all four:

1. App Store Connect → My Apps → New App: the name (it's reserved once created).
2. Domain: `lockin.app`, `getlockin.app`, `lockin.study`, `lockling.app` (Cloudflare Registrar).
3. TikTok, Instagram and YouTube handles.
4. A trademark search in your launch countries (IP Australia, USPTO) for focus or study apps.

The app's code uses `Lockin` in type names, bundle IDs and the Live Activity's attributes type
(`LockinAttributes`, which the server names in push-to-start payloads). A different store name
doesn't need any of that to change; the display name is `CFBundleDisplayName`, set per target in
`project.yml`.
