# news-digest — mission

> A "skill" is the prompt a scheduled LLM routine runs. Note what is here and what is NOT:
> the **mission** (judgment) is here; the **mechanics** are not — they live in the tools.

## Loadout — download at start

```bash
bash loadout.sh read_news notify
# (in a real project these tools live in a shared tools/ dir, and the loadout would also
#  list your write/publish tools, e.g.  loadout.sh read_news write_story notify publish_notion)
```

## Mission

Turn new headlines into a running ledger of stories:

- a repeat of a known fact → **skip**
- a new fact on an ongoing story → **extend** it
- a genuinely new event → **open** a story
- listicle / ad / noise → **skip**

Each morning, write a short briefing from the ledger and post it. Call `notify` and your
publish tool **separately** — decide, per judgment, whether each should fire. (Do not assume
"publishing" implies "notifying"; that's a policy, and policy is yours to choose each run.)

## Rules (these are judgment, not mechanics)

- Facts only — no buy/sell calls, no sentiment labels.
- Use numbers only if they appear in the source (no outside recall).

## On tool failure

If any tool exits non-zero, **stop immediately — do not retry**. The watermark only advances
at the very end, so a mid-run failure is safely resumed on the next run.
