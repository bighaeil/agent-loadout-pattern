# The Loadout Pattern: Handing the Wheel to an Autonomous LLM

> Most LLM integrations bolt a model *into* your code. This is about the opposite: letting the
> model **drive** your system — equipping itself, on its own initiative, with a **loadout**: the
> curated, self-describing set of tools it picks for each mission. The system stops being the
> program that calls an LLM, and becomes the *suit* the LLM wears.

*Audience: engineers building agentic/automation systems. There's code, and there's a bit of
philosophy — because the philosophy is what makes the code shaped the way it is.*

> **Two words, kept distinct (the whole post hinges on this):**
> a **toolbox** (or catalog) is *every* tool you own — the whole armory.
> A **loadout** is the curated subset a routine equips *for one mission* — what it actually suits
> up with. The entire MCP server is a toolbox; a loadout is the handful of tools one routine is
> handed at wake.

---

## The usual way, and the constraint hiding in it

In a typical LLM integration the model lives **inside** your process. Your code calls it:

```python
answer = agent.invoke({"input": "What changed in the market overnight?"})
```

This is great for **human-triggered** work: a person asks, the system fetches and answers. The
human is the caller; nothing happens until they show up. The LLM is a *component* — a function
your program calls and pays per token to use.

But a whole class of systems isn't human-triggered. They wake on a schedule and act on their own:
a routine that digests overnight news every hour, posts a morning briefing, watches a queue,
reconciles a ledger. Here the **caller is the routine itself**, not a person. And if you wake the
model on a cron — say, a headless Claude Code session every hour — the model is no longer a
component inside your program. It's *outside*, periodically taking the wheel.

That inversion changes what your system should be.

## The metaphor: you, the brain, and the suit

Three layers, and it matters which is which:

- **You** are Tony Stark — the owner. You delegate intent and occasionally override.
- **The LLM** is JARVIS — an AI that *operates the suit autonomously on your behalf*. It judges,
  acts, and reports. You don't micromanage it.
- **Your system** is the **suit** — sensors, memory, tools, power.

Here's the leverage that falls out of this: **you can't make JARVIS smarter.** The model is a
given. Every bit of engineering you do goes into the *suit* — what the brain can sense, remember,
and do. So the central question of the whole system becomes: *how do we equip the brain well — give
it the right loadout — and let it reach for the right tool at the right moment?*

## The problem: skills that tangle *mission* with *mechanics*

When you first wire a cron-woken routine, you write a prompt ("skill") that mixes two very
different things: the **mission** (what to judge, the actual work) and the **mechanics** (raw
`curl`, database queries, hardcoded IDs). A real before-state:

```text
# news-digest skill (before)
1. Query Mongo for new headlines since the watermark:
   docker exec db mongosh app --eval 'db.news.find({publishedAt:{$gt: ...}})...'
2. Decide which are new stories vs updates vs noise.  ← the actual mission
3. Post the briefing:
   curl -X POST http://localhost:9000/notify -d '{"type":"SIGNAL", ...}'
   Then create a Notion page: data_source_id "<your-notion-data-source>", icon "📰", ...
```

Two problems compound. First, the mission (step 2 — judgment) is drowned in plumbing. Second,
every *other* routine that needs to "post a notification" re-describes that same `curl` in its own
prompt. Change the notification URL and you edit five skills. The mechanics are copy-pasted prose.

## The pattern: a per-mission loadout + mission-only skills

Split the system along the seam between **interface** and **implementation**.

**1. Tools are small, dumb, independent scripts.** Each hides one piece of mechanics behind a
name. `notify` sends a notification. `read_news` reads. They don't know about each other. Together,
all of them are your **toolbox** (the catalog).

```bash
#!/usr/bin/env bash
# notify.sh — send a notification (hides the URL/payload mechanics)
set -euo pipefail
[ "${1:-}" = "--describe" ] && { echo "notify|action|send a notification"; exit 0; }
TYPE="$1"; TITLE="$2"; MSG="$3"
payload="$(jq -n --arg t "$TYPE" --arg ti "$TITLE" --arg m "$MSG" '{type:$t,title:$ti,message:$m}')"
curl -s -X POST "${NOTIFY_URL:-http://localhost:9000/notify}" \
     -H 'Content-Type: application/json' -d "$payload"
```

**2. Tools describe themselves.** One line, `--describe`, is the single source of truth for what
the tool is. Not the skill, not a wiki — the tool.

**3. A `loadout` assembler hands the brain its kit.** Given a list of tool *names* (the loadout),
it prints their self-descriptions. This is what the routine runs at wake — it *downloads its
loadout* from the toolbox.

```bash
#!/usr/bin/env bash
# loadout.sh <tool> [tool...] — print the self-descriptions of the named tools (the loadout)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "🧰 loadout for this mission"
for t in "$@"; do
  IFS='|' read -r name kind desc <<<"$(bash "$DIR/$t.sh" --describe)"
  echo "  - $name ($kind): $desc"
done
```

**4. The skill becomes *mission only*.** It states what to do and names its loadout. The
descriptions arrive *with the loadout*, not re-written in the skill:

```text
# news-digest skill (after)
## Loadout — download at start
bash tools/loadout.sh read_news write_story notify publish_notion

## Mission
Turn new headlines into a running ledger of stories: skip repeats, extend ongoing
stories, open new ones, ignore noise. Each morning, post a briefing from the ledger.
```

**5. The brain composes tools — it does not auto-chain them.** This is subtle and important.
`notify` and `publish_notion` stay separate. We do *not* make "writing to Notion" secretly also
send a notification. Why? Because the moment you fuse two tools in the plumbing, you've frozen a
policy — you can no longer publish quietly, or notify without publishing. Keep the tools
independent and let the *brain* decide to call both. Composition is judgment; it belongs to the
brain, not the wiring.

**From the model's point of view, this is the whole win.** When the routine wakes, it receives two
cleanly separated things: a **mission** — what to accomplish and how to judge it — and a
**loadout** — the named capabilities it is allowed to use. It never has to excavate the *how* (a
URL, a query, an ID) out of the *what*; the mechanics are simply not in its field of view, leaving
only the decision and the set of moves available to make it. The skill carries judgment (which
changes often); the toolbox carries capability (stable, shared); a loadout is just the names a
routine picks from it. A new routine lists tool names and gets their descriptions for free — change
a URL and you edit one tool, not five prompts.

## Observability: log the interface, not just the result

Side effects are not proof. A notification arriving does not establish that the model invoked the
tool, and a tool whose implementation is a no-op stub produces no side effect at all even when the
model used it correctly. Verifying behavior therefore means observing the **interface** — the
moment a tool is called — separately from what its implementation did.

Each tool logs at that boundary:

```bash
# _log.sh (sourced by every tool)
tlog() {  # tlog <event> [detail]   event: INVOKED | OK | DRY | ERR
  printf '%s | %-12s | %-7s | %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(basename "$0" .sh)" "$1" "${*:2}" \
    >> "$LOG_FILE"
}
```

The log separates two questions that side effects conflate:

```text
... | notify | INVOKED | SIGNAL | Morning briefing   # the interface was called
... | notify | OK      | SIGNAL HTTP 200             # the implementation sent it
... | notify | DRY     | SIGNAL                      # called, but did not send (DRY_RUN)
```

`INVOKED` records that the model used the tool, independent of any outcome; `OK`/`DRY`/`ERR`
records what the implementation did. Because the model depends on the interface rather than the
implementation, the same routine can run in a **shadow mode** — where `notify` only logs and never
sends — with no change in the model's behavior. The boundary log is also the reliable way to audit
a past run: it records what executed, not merely what the skill instructed.

## It's a pattern, by design

There is nothing here to install — no runtime, no base class, no inversion of control. The loadout
pattern is a *shape* for tools and skills, adopted incrementally: convert one tool, point one
routine at a loadout, and the rest of the system is untouched. It drops into any stack that can run
a script and a prompt, and it composes with whatever you already use to call models. Keep it a
pattern; reach for heavier machinery only when a concrete need forces it.

## Why it matters

Go back to the suit. You cannot upgrade the brain; it's the model you were given. Every lever you
have is in the equipment — what the brain can discover, reach for, and be observed using. A
self-describing, observable loadout is precisely how the brain *takes the wheel*: it wakes,
downloads the tools it's allowed, sees what it can do, and acts — and you can watch it do so at the
interface, not by guessing from side effects. The system stops being a program that occasionally
calls a model, and becomes a suit a model wears.

## Recipe (TL;DR)

1. **Tools** = small scripts, one capability each, mechanics hidden — together, your toolbox. Add a
   `--describe` line and a boundary log (`INVOKED` + `OK/DRY/ERR`). Side-effecting tools support a
   `DRY_RUN`.
2. **Loadout** = an assembler that prints a routine's named tools' self-descriptions. The routine
   runs it at wake to *download its loadout*.
3. **Skills** = mission (judgment) + a loadout list. No mechanics. Let the brain *compose* tools;
   never auto-chain them in the wiring.
4. **(Optional)** Add a pre-commit / CI check: every skill must carry a mission and a declared
   loadout, and no raw mechanics may leak into a skill body.

Runnable examples are in [`examples/`](examples/).

---

# 한국어 — 핸들을 넘겨라: 자율 LLM 루틴을 위한 도구상자 패턴

> 대부분의 LLM 통합은 모델을 당신 코드 *안에* 끼워 넣는다. 이 글은 그 반대다 — 모델이 시스템을
> **운전**하게 하고, 스스로 필요할 때 미션에 맞는 **도구상자**(영어로는 *loadout*: 골라 장착한 키트)를
> 꺼내 입게 하는 것. 시스템은 'LLM을 호출하는 프로그램'이 아니라, **LLM이 입는 슈트**가 된다.

*독자: 에이전트·자동화 시스템을 만드는 개발자. 코드도 있고 철학도 조금 있다 — 코드가 이런 모양인
이유가 그 철학에 있기 때문이다.*

> **두 말을 구분하면 또렷해진다:** **도구 창고(catalog)** 는 *가진 모든 도구*(MCP 전체가 여기). 한
> 루틴이 *이 미션을 위해 골라 장착하는 부분집합*이 **로드아웃**(이 글의 한국어 중심어로는 그 미션의
> "도구상자")이다. 두뇌는 깰 때 창고에서 자기 로드아웃을 내려받는다.

## 익숙한 방식과 그 안에 숨은 제약

보통의 LLM 통합에서 모델은 프로세스 **안에** 산다. 당신 코드가 부른다: `agent.invoke(...)`.
**사람이 트리거하는** 일엔 훌륭하다 — 사람이 묻고, 시스템이 가져와 답한다. 사람이 없으면 아무
일도 안 일어난다. LLM은 *부품*이고, 호출마다 토큰을 지불한다.

그런데 사람이 트리거하지 않는 시스템도 많다. 정해진 시각에 깨어나 스스로 행동하는 것들 — 매시간
뉴스를 정리하고 아침 브리핑을 올리는 루틴, 큐를 지켜보는 워처, 장부를 맞추는 작업. 여기서
**호출자는 사람이 아니라 루틴 자신**이다. cron이 헤드리스 LLM을 깨우면, 모델은 더 이상 프로그램
안의 부품이 아니다. *바깥에서* 주기적으로 핸들을 잡는다. 이 역전이 시스템의 형태를 바꾼다.

## 비유: 당신, 두뇌, 그리고 슈트

- **당신** = 토니 스타크, 주인. 의도를 위임하고 가끔 개입한다.
- **LLM** = 자비스. 당신을 대신해 *슈트를 자율로 운용하는 AI*. 판단·행동·보고한다.
- **시스템** = **슈트**. 감각·기억·도구·동력.

여기서 핵심 레버리지가 나온다: **자비스를 더 똑똑하게 만들 순 없다.** 모델은 주어진 것이다.
당신의 모든 엔지니어링은 *슈트*로 간다. 그래서 시스템의 핵심 질문은 이거다: *두뇌를 어떻게 잘
입히고(맞는 로드아웃을 쥐어주고), 적시에 맞는 도구를 잡게 할 것인가?*

## 문제: 미션과 mechanics가 뒤엉킨 스킬

cron 루틴을 처음 엮으면, 프롬프트("스킬")에 두 가지가 섞인다 — **미션**(판단, 실제 일)과
**mechanics**(생 `curl`, DB 쿼리, 하드코딩된 ID). 미션(판단)이 배관에 묻히고, *다른* 루틴마다 같은
`curl`을 자기 프롬프트에 또 적는다. 알림 URL 하나 바뀌면 스킬 다섯 개를 고친다. mechanics가
복붙된 산문이 된다.

## 패턴: 미션별 도구상자(로드아웃) + 미션만 있는 스킬

**인터페이스**와 **구현**의 경계를 따라 시스템을 가른다.

1. **도구 = 작고 멍청하고 독립적인 스크립트.** 각자 mechanics 하나를 이름 뒤에 숨긴다. `notify`는
   알림만, `read_news`는 읽기만. 서로 모른다. 이들 전체가 **도구 창고**다.
2. **도구가 스스로를 설명한다.** `--describe` 한 줄이 "이 도구가 무엇인가"의 단일 출처다.
3. **`loadout` 조립기가 두뇌에 도구상자를 건넨다.** 도구 *이름* 목록(로드아웃)을 주면 그 자기서술을
   모아 출력한다. 루틴은 깰 때 이걸 실행해 *창고에서 자기 도구상자를 내려받는다*.
4. **스킬은 *미션만*.** 무엇을 할지 + 로드아웃 이름. 설명은 스킬이 재서술하지 않고 *도구상자와 함께*
   온다.
5. **두뇌가 도구를 조합한다 — 자동 연쇄가 아니다.** `notify`와 `publish_notion`은 따로 둔다.
   "노션에 쓰면 자동으로 알림"으로 묶지 않는다. 두 도구를 배관에서 융합하는 순간 정책이 굳어버려서,
   조용히 발행하거나 발행 없이 알림만 보내는 자유를 잃는다. 도구는 독립으로 두고 *두뇌가* 둘 다
   부를지 정한다. 조합은 판단이고, 판단은 두뇌의 몫이다.

**두뇌 입장에서 보면, 이것이 핵심이다.** 루틴이 깨어날 때 받는 것은 깔끔하게 분리된 두 가지다 —
**미션**(무엇을 이뤄야 하고 어떻게 판단할지)과 **로드아웃**(쓸 수 있도록 허용된 능력의 이름들).
두뇌는 *어떻게*(URL·쿼리·ID)를 *무엇*에서 파낼 필요가 없다. mechanics는 아예 시야에 없고, 판단과
그 판단을 실행할 수단의 목록만 남는다. 스킬은 (자주 바뀌는) 판단을, 창고는 (안정적·공유되는) 능력을
담고, 로드아웃은 루틴이 창고에서 고른 이름들일 뿐이다. 새 루틴은 도구 이름만 적으면 설명이 따라오고,
URL이 바뀌면 도구 하나만 고친다.

## 관측 가능성 — 결과가 아니라 인터페이스를 기록한다

부작용은 증거가 아니다. 알림이 도착했다고 모델이 그 도구를 호출했다는 보장은 없고, 구현이 아무것도
하지 않는 stub이면 모델이 제대로 썼어도 부작용은 전혀 보이지 않는다. 그래서 동작 검증은 구현이 한
일과 별개로 **인터페이스**(도구가 호출된 순간)를 관측하는 일이 된다.

각 도구는 그 경계에서 로그를 남긴다:

```bash
# _log.sh (모든 도구가 source)
tlog() {  # tlog <event> [detail]   event: INVOKED | OK | DRY | ERR
  printf '%s | %-12s | %-7s | %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(basename "$0" .sh)" "$1" "${*:2}" \
    >> "$LOG_FILE"
}
```

로그는 부작용이 뭉뚱그리는 두 질문을 분리한다:

```text
... | notify | INVOKED | SIGNAL | 아침 브리핑   # 인터페이스가 호출됨
... | notify | OK      | SIGNAL HTTP 200       # 구현이 실제로 보냄
... | notify | DRY     | SIGNAL               # 호출됐지만 발송하지 않음 (DRY_RUN)
```

`INVOKED`는 결과와 무관하게 모델이 도구를 썼음을 기록하고, `OK`/`DRY`/`ERR`는 구현이 무엇을 했는지
기록한다. 모델은 구현이 아니라 인터페이스에 의존하므로, `notify`가 로그만 남기고 발송하지 않는
**shadow 모드**로 같은 루틴을 돌려도 모델의 동작은 달라지지 않는다. 이 경계 로그는 과거 실행을
감사하는 신뢰할 수 있는 방법이기도 하다 — 스킬이 무엇을 *지시*했는지가 아니라 무엇이 *실행*됐는지를
남기기 때문이다.

## 의도된 패턴이다

설치할 것이 없다 — 런타임도, 상속할 베이스 클래스도, 제어 역전도 없다. 로드아웃 패턴은 도구와
스킬의 *형태*이고, 점진적으로 도입한다: 도구 하나를 옮기고, 루틴 하나를 로드아웃에 연결하면 나머지
시스템은 그대로다. 스크립트와 프롬프트를 돌릴 수 있는 어떤 스택에도 끼워지고, 이미 쓰는 모델 호출
방식과도 공존한다. 패턴으로 두고, 더 무거운 장치는 구체적 필요가 강제할 때만 꺼내라.

## 왜 중요한가

다시 슈트로. 두뇌는 업그레이드할 수 없다 — 주어진 모델이다. 당신의 모든 레버는 장비에 있다. 두뇌가
발견하고, 잡고, *사용하는 게 관측되는* 도구. 자기서술적이고 관측 가능한 도구상자(로드아웃)가 바로
두뇌가 *핸들을 잡는* 방식이다 — 깨어나 허용된 도구를 내려받고, 할 수 있는 걸 보고, 행동한다. 그리고
당신은 부작용으로 추측하는 게 아니라 인터페이스에서 그걸 지켜본다.

## 레시피 (요약)

1. **도구** = 작은 스크립트, 능력 하나씩, mechanics 숨김 — 전체가 도구 창고. `--describe` + 경계
   로그(`INVOKED` + `OK/DRY/ERR`). 부작용 도구는 `DRY_RUN` 지원.
2. **로드아웃** = 한 루틴이 고른 도구들의 자기서술을 출력하는 조립기. 루틴이 깰 때 실행해 *도구상자를
   내려받음*.
3. **스킬** = 미션(판단) + 로드아웃 목록. mechanics 없음. 두뇌가 도구를 *조합*하게 하고, 배관에서
   자동 연쇄하지 마라.
4. **(선택)** pre-commit / CI 체크 추가: 모든 스킬은 미션과 선언된 로드아웃을 갖고, 스킬 본문에 생
   mechanics가 새지 않도록.

실행 가능한 예시는 [`examples/`](examples/)에 있다.
