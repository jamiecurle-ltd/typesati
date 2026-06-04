<p align="center">
  <img src="Resources/icon.png" width="128" alt="typesati icon">
</p>

**Deliberate typing practice shouldn’t stop when the typing test ends.**

# The idea

**type**: using a keyboard.

**sati**: (Pāli: _sati_, Sanskrit: _smṛti_) mindfulness, awareness, recollection, noticing and intention.

**typesati**: “Typing with awareness and intention" (_and equally importantly – available as an app domain_)

Typesati is a tiny macOS menu bar app that estimates typing accuracy by counting backspace presses relative to all other key presses.

Perhaps it will even put you on the path to typing enlightenment: thinking clearly and accurately through your fingers at 100+ words per minute. At least the club fingered author hopes.


When you're working and you feel like you want to practice deliberately, just start a session. Continue working as normal. Typesati quietly compiles metrics about your session.


While a session is recording, the menu shows:

- **Key presses** — backspaces vs. other keys
- **Accuracy** — % of presses that aren't backspace (optionally shown in the menu bar)
- **Streaks** — current and longest run of keys between backspaces, with duration and WPM
- **Words per minute** — over the whole session

# The problem

Learning to touch type accurately is hard and requires practice. 

Apps like [monkeytype](https://monkeytype.com) and [keybr](keybr.com) are great for deliberate practice. As soon as you leave those environments though, there's a temptation to cease practicing mindfully.

The problem is that deliberate practice often happens in isolated environments, while most typing happens elsewhere. Over time a gap develops between how you type during practice and how you type during real work.

Typesati helps close that gap.


# Privacy

**Typesati measures typing behaviour, not typing content.**

It's reasonable to be cautious about any application that monitors typing. Typesati is designed to be privacy-first.

Typesati does not record what you type. It never stores characters, words, text, keycodes, or timestamps.

Every keypress is classified immediately as one of the following:

- backspace
- other

The original key information is discarded instantly and cannot be recovered. As a result, Typesati has no way to reconstruct what you typed.

The application stores only aggregate statistics, such as counts of backspaces and other keypresses. Streaks are tracked in memory, and only the longest streak for a session may be persisted.

All data is stored locally in an SQLite database on your machine. No typing data is sent to external servers. You're free to inspect, export, or delete the database at any time.

Delete the database, and the data is gone.

Typesati does not store prompts, responses, documents, or any text entered by you. It records only the counts of your keystrokes. 

# Unavoidable permission grant

Typesati requires macOS **Input Monitoring** permission in order to observe keypress events.

On first launch, grant the permission in System Settings and relaunch the app.

Without this permission, Typesati cannot function.



# License

Typesati is source-available under BSL 1.1. Personal use and internal business use are permitted. Offering Typesati or a derivative as a competing SaaS or hosted service requires a commercial license. On 2030-06-03, this version will convert to Apache License 2.0.
