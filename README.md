# Vulcan RunBook

A dungeon and raid run log for **World of Warcraft: Forever**. It starts on its own when you
zone into a dungeon or raid and records the run: clear time, boss splits against your best
run, deaths and wipes, drops, gold and XP, and notes. Your history keeps per-dungeon stats and
best times. If your partner runs it too, each log also shows the other's gold, XP, drops and
notes. The Group tab shows everyone in your group or raid, with the gold and XP of each player
who runs it.

**Display only, no automation.** RunBook reads what happens and shows it. It never casts,
targets, moves, loots, rolls, resets or clicks anything for you. What it sends to your group is
listed under [Duo sync](#duo-sync).

Part of the **Vulcan Suite**: Vulcan GrindWatch · Vulcan DuoQuest · Vulcan SimBench.

## Quick start

1. **Install.** With the **CurseForge app** or **WowUp**, search for *Vulcan RunBook* and
   install it for World of Warcraft: Forever. By hand: unzip the download and copy the
   `VulcanRunBook` folder into the `Interface\AddOns\` folder of your Forever game folder
   (Battle.net > the Forever game > gear icon > *Show in Explorer*). At the character screen,
   click **AddOns**, make sure Vulcan RunBook is ticked, and tick **Load out of date AddOns**
   if it's greyed out.
2. **Playing as a pair? Both of you install it.** If you're friends in game (friends list or
   Battle.net), you pair up on your own in any group, about half a minute after you're both
   in a run; in a two-person group, anyone does, at once. You get a chat line either way. To
   be sure, set each other: `/runbook partner Mirel` (and your partner types
   `/runbook partner Tavlius`; for someone on another realm, add it:
   `/runbook partner Mirel-Emberfall`). When your partner plays another character on the
   same Battle.net account, your log follows them there.
3. **Run one dungeon, then type `/runbook check`** (see "First time in-game" below). It
   tells you whether Forever reports boss kills to addons.
4. **If it doesn't,** mark each boss as it dies: `/runbook boss <name>`, or set the
   "Mark a boss kill" key (Options > Key Bindings > AddOns). Let one of you do it;
   the other's log gets it through sync.

`/runbook` shows or hides the live window, `/runbook history` opens the history, and
`/runbook help` lists the commands. Key bindings (Options > Key Bindings > AddOns > Vulcan
RunBook): show/hide the live window, open the history, and mark a boss kill.

## Fixing mistakes

| Oops | Fix |
| --- | --- |
| Marked the wrong boss | `/runbook unboss` (or `/runbook unboss #12` for run #12). If that mark was of a boss killed before your last trip outside, it also started a new run, and that stays. |
| A run you didn't want | `/runbook delete 12` (the number is in the history), then the same again within 15 seconds to confirm |
| Ended a run by mistake | `/runbook start` reopens it, while you're still inside the dungeon you ended it in |
| Typed `/runbook new` | On a run with kills or a few minutes in, it asks you to type it again within 15 seconds first. Once done, it can't be undone. |
| The dungeon was reset and RunBook didn't notice | `/runbook new` inside |
| The final boss is wrong | `/runbook final <boss name>` (`/runbook final auto` undoes it) |
| A note on the wrong run | Notes can't be removed; add a corrected one with `/runbook note #12 <text>` |

## How a run works

| What happens | What RunBook does |
| --- | --- |
| You zone into a dungeon or raid | A run starts, or the one you left resumes. |
| You leave and come back (repairs, a corpse run) | Same run. Time outside doesn't count, except up to 10 minutes running back as a ghost. |
| The dungeon is reset (you see the message, or your partner's RunBook does) | The run ends; going back in starts a new one. |
| A boss that died earlier in this copy dies again | The dungeon was reset without either of you seeing it. Everything since you last came back in alive after that kill (or as a ghost, if you didn't come back alive) becomes a new run. (Only named kills can show this.) |
| You enter a different dungeon, Scarlet Monastery wing or difficulty | The old run ends and a new one starts. Walking between floors never does. |
| You're outside, alive, for 30 minutes (2 hours for raids) | The run ends. A raid you go back into before the weekly reset, or a dungeon your partner stayed inside, carries on in the same copy: no new instance-cap entry, and its clear time doesn't count as a whole one. |
| `/runbook end` | Ends it now. It won't restart until you leave; `/runbook start` reopens it. Going back into the same copy later starts a new run without counting toward the instance cap again. |
| `/runbook new` | Ends it and starts a fresh run where you stand, as a new instance. Your partner's run starts over too (if they're outside, theirs ends, and your kills until they're back go to their new one). Only use it for a real new copy: RunBook takes your word for it. |

Runs under a minute with nothing in them (zoned in by mistake) aren't saved.

Why: Forever hides creature IDs inside instances, so an addon can't tell two copies
of a dungeon apart. The reset message goes to whoever reset, so sync passes it on,
and a boss dying twice catches resets by someone else (a pug leader). In Classic a
new group also gets a new copy without any message: if your group changes while
you're outside, RunBook reminds you to type `/runbook new` if that happened.

Scarlet Monastery's and Dire Maul's wings share one dungeon ID. In Scarlet Monastery
each wing is its own map, so each wing gets its own runs and stats (unconfirmed until
tested in-game). Dire Maul's wings can't be told apart: type `/runbook new` when you
switch wings (you get a reminder once per session). A reset message doesn't say which
wing was reset, so it never splits the wing you're in. Stratholme's two sides and
Lower/Upper Blackrock Spire are one copy each, as in Classic.

## The live window

Shows inside dungeons and during a ghost run (`/runbook auto off` stops that).

- **Name and clock.** "(paused)" when you've stepped out, "(ghost)" while running back.
- **Bosses 3/5 · best 28:40.** Each kill with its split against your fastest clear
  (green ahead, red behind), compared when the boss died at the same point in both
  runs. Your first run of a dungeon shows just "Bosses 3".
- **Wipes and deaths** with names, then "+N" for the rest. In a raid, only you two's
  deaths are counted - here, in the history and in the stats (a run's details add a
  count of everyone else's).
- **You / partner** gold (coin + loot value) and XP, per-hour rates after 5 minutes,
  and a **Together** total (shown to the silver, so they add up).
- **Drops:** the latest four. Yours and your partner's from green up, other players'
  from blue up (in a raid, only you two's).
- **Group (5 with RunBook): 12g · 40k XP** in a group where others run it too (the
  Group tab has each player).
- **The latest note** and the **instance cap** line.

Right-click the window for the history. Drag to move; `/runbook lock`, `/runbook scale 1.2`.

## Clears and best times

The **final boss** of a dungeon is the boss your full runs end on (runs with as many
kills as your biggest one, or one fewer, vote with their last kill). One run is
enough, so splits start on your second run; raids wait for two nights ending on the
same boss. A run that killed the final boss is a **clear**; its clear time is when
it did. Best times and splits come from your fastest clear of the whole dungeon.
These are clears, but don't count for best or average times: a run that began in a
copy where bosses had already died (back in after `/runbook end` or a break; its
details say so), and one where a boss your partner killed while you were outside (not
running back) has no real time in your run. A route that skips bosses (a tribute run)
counts like any clear; a run you joined part way does too, so delete it
(`/runbook delete`) if it would spoil your best time.

**Marking kills by hand.** `/runbook boss Edwin VanCleef` or the key. A second press
within 10 seconds is ignored. Unnamed marks are "Boss 1", "Boss 2"... in order (so
in a dungeon with optional bosses, name them); to name one, type `/runbook boss <name>`
within 10 seconds. A name you type is matched to how you wrote it before in that
dungeon ("VanCleef" becomes "Edwin VanCleef"). If the game reports the kill within
10 seconds of your mark, it's the same kill (unless it names a different boss). Between the two of you: one's mark and
the other's press within 20 seconds are one kill, and so are two spellings of the
same name ("Bael'Gar", "Baelgar"; "Malor", "Malor the Zealous"). Two different names
are two kills (Sneed's Shredder and Sneed die seconds apart).
A boss your partner marks that your log already has stays one kill.

## History and stats

`/runbook history` lists the last 200 runs, newest first. Each has a fixed number
(#12); `*` means it has a note. Click one for its splits, deaths, gold and XP (yours,
your partner's and together), drops and notes. The **Dungeons** tab (`/runbook stats`)
shows per dungeon: runs, clears, best and average clear, gold/hr (yours and together),
XP/hr, deaths per run, wipes and blue/epic drops. Older runs (up to 2,000) are kept
in short form for the stats only: times, bosses, gold, XP and counts, without notes
or drop lists. They aren't listed, but `/runbook delete <#>` still removes one (say, a
best time you don't want: the Dungeons tab shows the best run's number).

**The Group tab** (`/runbook group`) shows your run in progress (or your last run):
every player who was in the group, most gold first, with gold, XP and rates from
each one who runs RunBook, and deaths and drops from your own log for everyone
(players without it show "no RunBook"). An "All of you" line adds up those with
numbers. A run's details show the same in a **Group** section. It's for showing
only: other players' numbers never go into your gold, the Together line, the stats
or best times, and nothing they send can change your run. Each player's numbers count
from when your run began (or from their first message, if they were already in a run).
A raid's worth (40 players) is kept per run. Short-form runs don't keep it.

**All your characters share one history** and one set of best times. With more than
one character in it, each row shows whose run it was, and `clear yes` asks you to type
it again, since it clears every character's runs.

## Commands

`/runbook`, then (the older `/runlog` and `/rlog` still work too):

| Command | Does |
| --- | --- |
| *(nothing)* | show/hide the live window (`show` / `hide` also work) |
| `history`, `stats`, `group` | the history window, on Runs, Dungeons or Group |
| `note <text>` | note on this run (or your last). Syncs to your partner. |
| `note #12 <text>` | note on run #12 |
| `boss [name]` | mark a boss kill by hand (also a key binding) |
| `unboss [#12]` | take back the last boss kill of this run (or your last run, or run #12) |
| `final <boss>` / `final auto` / `final` | set a dungeon's final boss, go back to automatic, or show it |
| `end`, `start`, `new` | end the run, reopen it, or start over as a new instance |
| `report [group/party/raid/instance/guild/say/w Name]` | share the run summary and blue+ drops (no channel: just to you) |
| `export` | the last 200 runs as CSV in a copy box (Ctrl+C) for a spreadsheet: times, splits, deaths, gold, XP, blue+ drops, notes, and the group's totals (players with RunBook, their gold and XP, you included) |
| `partner <name>` / `partner <name> alt` / `partner off` / `partner` | who you sync with; `alt`: it's your partner on another character (what their first character made stays in Together); `off` goes back to picking one on its own (a friend, or the only other player); just the word shows who |
| `quiet [on/off]` | no chat line per boss kill or run start |
| `cap [n/off]`, `cap day [n/off]` | instance cap per hour, and per day |
| `quality 0-5` | lowest quality of your and your partner's drops that's **recorded** (2 = green). Drops below it aren't kept, so raising it doesn't hide old ones and lowering it doesn't bring any back. Your partner's log always sends greens and up; below green, both of you need the lower setting. |
| `price vendor/ah` | loot value at vendor or Auctionator prices |
| `delete <run #>`, `clear yes` | remove one run (asks you to repeat it), or all of them |
| `auto on/off`, `sync on/off` | the live window showing itself in dungeons; duo sync (just the word shows the setting) |
| `lock`, `unlock`, `scale <0.5-2>`, `resetpos` | the live window |
| `backup`, `restore` | all your runs and settings as text to keep outside the game, and pasting one back (also the **Backup** and **Restore** buttons in the history window) |
| `check`, `debug on/off/echo/clear`, `export debug` | troubleshooting |

## Instance cap (unconfirmed for Forever)

Classic allowed 5 new instances an hour and 30 a day, per realm. RunBook assumes the
same and shows "Instances 3/5 this hour" (and a second line with the day's count
once you're within 5 of 30). At the cap it shows when you're under it again, and says once when a slot
frees up. If the game lets you in past the cap, it says so once: Forever's limit may
be higher (`/runbook cap 6`). `/runbook cap off` and `/runbook cap day off` hide them.

Entries are counted for all your characters on this PC, on every realm. Entries
made on another PC or before you installed RunBook aren't. Coming back into the same
copy doesn't count again, and neither does `/runbook start` after `end`.

## Duo sync

Your partner is whoever you set with `/runbook partner`. Until you set one, it's the
first RunBook user you're in a two-person group with (from their first message; not
someone you first heard in a bigger group, like a dungeon-finder group thinning out),
or a friend of yours (friends list or Battle.net) who runs it, in a group of any size:
35 seconds after the first friend is heard, if they're the only friend still in your
group who runs it (what they sent meanwhile - drops, notes, kills - is taken then). A
friend on another RunBook version is never picked. With several friends, none is
picked and you're told to pick one; that holds while you're in that group (a
`/reload` too, which also keeps what a waited-on friend sent). A friend heard after
one was picked gets a chat line, in a raid too.
Someone from another realm with a friend's name isn't your friend. Their realm
is remembered, so someone with the same name on another realm isn't taken for them. When your partner is a Battle.net friend, their BattleTag is
kept too: if they turn up on another character of the same account, that character
becomes your partner (with a chat line; `/runbook partner <old name>` switches back),
unless your partner's character is online in your group. Then, a character of theirs
that has synced with you as your partner before adds its gold and XP to theirs (its
drops and notes aren't taken); one that hasn't goes to the Group tab until you use
`/runbook partner <name> alt`. Their characters count as one partner: what each made
stays in your Together line, and their deaths and drops are "you two's". When the game doesn't
show their BattleTag (players hidden inside), you get a line suggesting `/runbook
partner <name> alt`, which says it's them. A bare name means the player
on your realm (or your partner's realm, if it's your partner); `/runbook partner
Name-Realm` picks someone on another realm.
A friend with another BattleTag never takes your partner's place. When you change
partner to someone else (or turn it off) during a run - or between `/runbook end` and
`/runbook start` - what the old one made in it so far moves to the Group tab, so it's
no longer in your Together line. Other RunBook users
(a pug, a raid) only reach the Group tab: their gold and XP are shown there and
nothing else of theirs is used. Messages are only taken from your group's
channel, from someone in your group. What can't be sent yet (a busy moment, a boss
fight) waits, also over a `/reload`, logout or a short break in the group, for up to 10
minutes.

While you're grouped, each of you sends your gold and XP (when they change), your
notable drops, your boss kills (so a kill one of you missed while dead or outside
still counts), your notes and any reset you saw. Each kill says when it died, so
when your partner kills a boss your log saw die minutes earlier, both logs know the
dungeon was reset.

Each run of yours shows what your partner made *while it was going*, so if one of
you starts over and the other doesn't, each run still gets the right share. Gold,
XP, drops and kills aren't sent while the sender has no run going.

- Messages wait during boss fights (Forever blocks them) and go out after.
- A drop you'd also see in a loot message isn't counted twice.
- If you two run different versions, you'll both get a one-time message and sync stays
  off until you match. `/runbook sync off` turns it off.

**What it sends.** Addon messages go to your **party, raid or instance group only**, never to
whispers, guild or public channels, and only while sync is on. Every message carries RunBook's
sync protocol number, a random tag for your session, and the dungeon's map ID, name, wing and
start time. On top of that, each kind carries:

| Message | Contents |
| --- | --- |
| Stats | your run's time, coin, loot value (vendor and auction), XP, kills, and whether it ended |
| Drop | the item ID, count and quality of a notable drop, and when it dropped |
| Boss | the boss's encounter ID and name, when it died, and when you entered |
| Note | the text of a note you add |
| Split, new run, reset | that you came back in, started over, or saw a reset message (with the dungeon's name) |

Nothing else is sent: no character details, no location outside the dungeon, no history.

## First time in-game: a 5-minute check

The addon was tested against a simulated client. On Forever itself:

1. `/runbook debug on`, then run a dungeon with a boss or two.
2. `/runbook check`. Look for:
   - **Boss events** above 0 after a kill. If they stay 0, mark kills by hand.
   - **Loot lines read** above 0. If only "hidden by the client" goes up, your drops
     come from your bags and your partner's through sync, but other players' won't show.
   - **Resets** matched after a reset (if they don't, use `/runbook new` after resets).
   - **Group**: names and alive/dead readable for everyone (otherwise others' deaths
     can't be logged).
   - **Sync**: prefix registered, your partner's name, a recent last message, and
     "Kills this run" the same in both logs (if not, `/runbook boss` or `/runbook unboss`
     on the side that's wrong).
   - **Friends**: Battle.net and friends list "readable" (if not, set your partner by
     hand), and in a group with other RunBook users, "group view: N other players".
   - **Wing** readable in Scarlet Monastery.
3. `/runbook export debug`, Ctrl+C, and attach it to a bug report on the project's GitHub
   issues page so anything off can be fixed.

## Limits

- No combat data. Boss kills come from encounter events, deaths from the death event
  (yours) and party frames (others). A death and resurrection inside one boss fight
  (a soulstone) can be missed. A death out in the open world isn't counted when the
  game shows where they are.
- Gold is coin you picked up plus the value of items you got inside (soulbound ones
  too, at vendor price): what the run brought in, not profit after repairs, ammo or
  potions. Vendor, mail and trade money and purchases are left out. While the game
  hides loot messages, a new item in your bags counts as loot.
- Time inside counts even when you're away from the keyboard. Hunter pets' deaths
  aren't counted.
- A reset neither log sees directly is found only when a named boss dies twice in what
  looked like one copy; until then the run holds both copies. The split goes where you
  last came back in alive after that kill (a ghost return only if there was none),
  since a reset while you lie dead inside is the less likely one. If that guess was
  early, another boss killed twice splits it again at your later return.
  `/runbook end` or `/runbook new` in between can hide it.
- A saved raid is known by the weekly reset time the game gives
  (`C_DateAndTime.GetSecondsUntilWeeklyReset`, unconfirmed on Forever); without it, a
  raid night more than 2 hours after the last one starts a fresh-looking run.
- When the game hides players' names inside (unconfirmed on Forever), your partner
  counts as "online with you" for 5 minutes after their last message, so a relog onto
  a character of theirs you know counts only its gold and XP for up to 5 minutes.
- Messages can be held up in boss fights; a note, mark or `/runbook new` sent right then
  can be missed.
- Each character's saved file holds a copy of the history (see the next section), a few MB
  at most after a year or more of play.
- A message from your partner sent before your run began (held up while you came in
  or started over) isn't put in your run.

## Known Forever client issue: saved data

The Forever beta client has been reported to write add-on data to disk but sometimes fail to
load it back, and then overwrite the good file the next time you log out or /reload. Add-ons
can't read or write files, so RunBook does what's possible from inside the game:

- **Two copies.** Your account file holds your runs and settings, and each character's file
  holds a full copy. The two are merged at every login, so if one fails to load, the other
  fills in.
- **A warning when a load fails.** If the account file comes back empty, RunBook says so in a
  window that opens. Runs your other characters saved since this one's last logout are then
  only in the file on disk, so copy it before you log out or /reload. A character file that
  didn't load is spotted too: the account file lists the characters that have data. If both
  fail at once, it looks exactly like a fresh install and can't be detected, so keep a backup.
- **`/runbook backup`** (or the **Backup** button in the history window) gives you all your
  runs and settings as one line of compressed text. Paste it into a text file somewhere safe.
  **`/runbook restore`** puts it back. It checks the text is complete, undamaged, and from
  RunBook, and shows what it holds before you confirm. Runs you have now that aren't in the
  backup are kept. RunBook suggests a backup when a run ends, at most once a week.
- **Backing up by hand:** with the game closed, copy the `WTF` folder in your Forever game
  folder. RunBook's files are `WTF\Account\<account>\SavedVariables\VulcanRunBook.lua`
  (runs and settings) and `WTF\Account\<account>\<realm>\<character>\SavedVariables\VulcanRunBook.lua`
  (that character's copy and run in progress).

Community workaround tools exist. RunBook doesn't need or rely on any of them, and some work by
editing add-on files that your add-on updater replaces.

## Development

The repository is the add-on folder. Run every check (luacheck, the test suites, the fuzzers,
the mutation checks, the personal-data guard, and a real package build) in the pinned
container, from Git Bash or any shell with Docker:

    sh tests/docker.sh

After cloning (or right after `git init`), run this once before the first commit, from Git Bash on Windows (PowerShell has no `sh`). It sets this repository's commit identity and installs a pre-push hook that runs the personal-data guard over the tree and the whole history:

    sh tests/init_repo.sh

Commits must carry a GitHub noreply email address (`<id>+<username>` at `users.noreply.github.com`); the guard refuses any other address.

The GitHub Actions workflow runs exactly the same container on every push and pull request.
Pushing a tag `vX.Y.Z` packages the add-on with the BigWigs packager and uploads it to
CurseForge and Wago. The tag needs a matching `## vX.Y.Z` section in `CHANGELOG.md`.

- **Client version:** `## Interface: 16001` matches Forever 1.60.1. When the Forever client
  version changes, bump it in `VulcanRunBook.toc` and in `tests/tests_release.lua`.
- **Version:** the TOC's `## Version:` line holds the packager's version token (`project-version` between two `@` signs), and the packager replaces it with
  the tag. `/runbook check` shows it, or `dev` when running from source. Sync compatibility
  goes by the protocol number in `Sync.lua`, never the version.
- **Retiring the saved-data safety layer** once Blizzard fixes the client: delete
  `Persist.lua` and its TOC line, `tests/tests_persist.lua`, and `Libs/LibDeflate` (with its TOC
  line) if nothing else uses it. Then remove the backup and restore rows and the "Known Forever
  client issue" section from this README. The rest of the add-on only reaches that module
  through `ns.Persist` / `ns.extra*` checks. (The two-copy merge in `Data.lua` predates the
  module and is part of RunBook itself.)

## Credits

Backups are compressed with **LibDeflate** by Haoqian He (zlib License), included as a trimmed
copy in `Libs/LibDeflate`. Its license file is next to it, and the file says what was changed.

## License

MIT. See [LICENSE](LICENSE). Changes are listed in [CHANGELOG.md](CHANGELOG.md).
