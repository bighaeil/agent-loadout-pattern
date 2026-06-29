# The Loadout Pattern: Handing the Wheel to an Autonomous LLM

## The core idea

Conventional automation **executes** a procedure — code runs a fixed sequence of steps and decides
nothing; same input, same path, every time. The loadout pattern keeps the steps but moves the
*deciding* to the model. At each step the **brain** — an autonomous LLM — **judges**: what matters,
which tool to reach for, whether to act at all. It's handed a **purpose** and the latitude to pursue
it, and it *drives* — choosing its own tools as it goes. **Code executes; the brain decides.** Those
tools come as a **loadout** — a curated, self-describing set drawn from a shared **toolbox** — and
the brain is observed at the **interface** it calls, not by the side effects it leaves behind. The
model is the driver; your system is the suit it wears. Everything below is how to build that.

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

This post is about the other mode: **the LLM doing the work on its own initiative.** A routine wakes
on a schedule and gets on with it — digesting overnight news every hour, posting a morning briefing,
watching a queue, reconciling a ledger. No one asked; the routine is its own caller. Wake the model
on a cron — say, a headless Claude Code session every hour — and it is no longer a component inside
your program. It's *outside*, periodically taking the wheel and deciding what to do.

The line that matters isn't human-vs-cron — and it isn't even steps-or-no-steps. It's **executing
versus deciding**: a script runs its steps and decides nothing, while the brain — even when it
follows steps — *decides* at each one, choosing its own tools toward the goal.

That inversion changes what your system should be.

## The metaphor: you, the brain, and the suit

Three layers, and it matters which is which:

- **You** are Tony Stark — the owner. You delegate intent and occasionally override.
- **The LLM is JARVIS — the *brain*.** An AI that *operates the suit autonomously on your behalf*:
  it judges, acts, and reports, and you don't micromanage it. (Throughout this post, "the brain"
  means exactly this — the LLM that drives.)
- **Your system** is the **suit** — sensors, memory, tools, power.

Here's the leverage that falls out of this: **you don't hand-author JARVIS's intelligence.** It
comes from the model — and it improves when you swap in a better model, not when you write more
code. What you *build* is the *suit* — what the brain can sense, remember, and do. So the central
question of the whole system becomes: *how do we equip the brain well — give it the right loadout —
and let it reach for the right tool at the right moment?*

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

**1. Tools are named capabilities — a stable name over a swappable implementation.** Most are small,
dumb, independent scripts, but the *name* is the only thing the brain depends on; what sits behind
it is free to vary. Usually it wraps mechanics (a `curl`, a DB query, a stubbed no-op, a different
backend tomorrow). But a tool can just as well **hand off to another agent** — a sub-brain with its
own loadout — or **trigger the next task** in a pipeline. To the brain it's all the same: a name it
can reach for. So a tool is sometimes an interface over mechanics, and sometimes the *next move* —
another agent, or the start of the next step. `notify` sends a notification; `read_news` reads. They
don't know about each other. Together, all of them are your **toolbox** (the catalog).

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

**5. The brain thinks for itself — tools don't auto-chain.** Keep `notify` and `publish_notion`
separate; do *not* make "writing to Notion" secretly also send a notification. The moment you fuse
two tools in the plumbing you've frozen a policy — you can no longer publish quietly, or notify
without publishing. Leave the tools independent and let the *brain* reason about whether to call one,
the other, or both. The thinking is the brain's job; the wiring must not pre-decide it.

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

## A pattern, and its limit

This is a pattern, not a framework — and that's its honest limit: **nothing enforces it at
runtime.** There's no base class, no inversion of control, nothing that *prevents* a routine from
ignoring its loadout or inlining raw mechanics again. Adherence is a matter of discipline — or, if
you want a guardrail, a CI check that every skill carries a mission and a declared loadout. What
you get in exchange is lightness: nothing to install, and incremental adoption — one tool, one
routine at a time, in any stack that runs a script and a prompt.

## Why it matters

Go back to the suit. You upgrade the brain by adopting a better model — that's not code you write,
it's a model you swap in. Your day-to-day engineering goes into the equipment: what the brain can
discover, reach for, and be observed using. And because the brain depends on interfaces — a loadout
of named tools — the suit is model-agnostic: change the model and the same loadout still fits. A
self-describing, observable loadout is precisely how the brain *takes the wheel*: it wakes,
downloads the tools it's allowed, sees what it can do, and acts — and you can watch it do so at the
interface, not by guessing from side effects. The system stops being a program that occasionally
calls a model, and becomes a suit a capable model wears.

## Recipe (TL;DR)

1. **Tools** = small scripts, one capability each, mechanics hidden — together, your toolbox. Add a
   `--describe` line and a boundary log (`INVOKED` + `OK/DRY/ERR`). Side-effecting tools support a
   `DRY_RUN`.
2. **Loadout** = an assembler that prints a routine's named tools' self-descriptions. The routine
   runs it at wake to *download its loadout*.
3. **Skills** = mission (judgment) + a loadout list. No mechanics. Let the brain *compose* tools;
   never auto-chain them in the wiring.

Runnable examples are in [`examples/`](examples/).

---

# 한국어 — 핸들을 넘겨라: 자율 LLM 루틴을 위한 도구상자 패턴

## 핵심

보통의 자동화는 **절차를 실행**한다 — 코드가 고정된 단계의 나열을 돌릴 뿐 아무것도 판단하지 않는다;
같은 입력이면 늘 같은 경로. 로드아웃 패턴은 단계는 남기되 *판단*을 모델로 옮긴다. 각 단계에서 **두뇌**
— 자율 LLM — 가 **판단한다**: 무엇이 중요한지, 어떤 도구를 잡을지, 아예 행동할지 말지. 두뇌는 고정된
경로가 아니라 **목적**과 그것을 좇을 재량을 받고, 직접 *운전*한다 — 가면서 자기 도구를 고른다.
**코드는 실행하고, 두뇌는 판단한다.** 그 도구들은 공용 **도구 창고**에서 뽑아 장착한
**로드아웃**(미션별로 큐레이션된 자기서술 묶음)으로 오고, 두뇌는 남긴 부작용이 아니라 *호출한*
**인터페이스**에서 관측된다. 모델이 운전자이고, 시스템은 그가 입는 슈트다. 아래 내용은 전부 그것을
어떻게 짓는가다.

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

이 글이 다루는 건 다른 쪽이다 — **LLM이 스스로 알아서 하는 것.** 루틴이 정해진 시각에 깨어나 스스로
일을 해낸다 — 매시간 뉴스를 정리하고 아침 브리핑을 올리고, 큐를 지켜보고, 장부를 맞춘다. 아무도
시키지 않았다. 루틴이 자기 자신의 호출자다. cron이 헤드리스 LLM을 깨우면, 모델은 더 이상 프로그램
안의 부품이 아니다. *바깥에서* 주기적으로 핸들을 잡고 무엇을 할지 스스로 정한다.

핵심 경계는 사람이냐 cron이냐가 아니다 — 단계가 있느냐 없느냐도 아니다. **실행하느냐, 판단하느냐**다.
스크립트는 단계를 돌릴 뿐 아무것도 판단하지 않지만, 두뇌는 단계를 따르더라도 매 단계에서 *판단*한다 —
목적을 향해 자기 도구를 고르면서.

이 역전이 시스템의 형태를 바꾼다.

## 비유: 당신, 두뇌, 그리고 슈트

- **당신** = 토니 스타크, 주인. 의도를 위임하고 가끔 개입한다.
- **LLM = 자비스 = *두뇌*.** 당신을 대신해 *슈트를 자율로 운용하는 AI* — 판단·행동·보고하며, 당신이
  일일이 지시하지 않는다. (이 글에서 "두뇌"는 줄곧 이것을 가리킨다 — 운전하는 LLM.)
- **시스템** = **슈트**. 감각·기억·도구·동력.

여기서 핵심 레버리지가 나온다: **자비스의 지능은 당신이 손으로 짜는 게 아니다.** 그건 모델에서 오고,
더 나은 모델로 갈아끼울 때 좋아지지 코드를 더 쓴다고 좋아지지 않는다. 당신이 *만드는* 것은 *슈트* —
두뇌가 감각·기억·실행할 수 있는 것. 그래서 시스템의 핵심 질문은 이거다: *두뇌를 어떻게 잘
입히고(맞는 로드아웃을 쥐어주고), 적시에 맞는 도구를 잡게 할 것인가?*

## 문제: 미션과 mechanics가 뒤엉킨 스킬

cron 루틴을 처음 엮으면, 프롬프트("스킬")에 두 가지가 섞인다 — **미션**(판단, 실제 일)과
**mechanics**(생 `curl`, DB 쿼리, 하드코딩된 ID). 미션(판단)이 배관에 묻히고, *다른* 루틴마다 같은
`curl`을 자기 프롬프트에 또 적는다. 알림 URL 하나 바뀌면 스킬 다섯 개를 고친다. mechanics가
복붙된 산문이 된다.

## 패턴: 미션별 도구상자(로드아웃) + 미션만 있는 스킬

**인터페이스**와 **구현**의 경계를 따라 시스템을 가른다.

1. **도구 = 이름 붙은 능력 — 교체 가능한 구현 위에 놓인 안정적 이름(인터페이스).** 대부분은 작고
   멍청하고 독립적인 스크립트지만, 두뇌가 의존하는 건 *이름*뿐이고 그 뒤는 자유롭게 달라질 수 있다.
   보통은 mechanics를 감싼다(`curl`·DB 쿼리·아무것도 안 하는 stub·내일 다른 백엔드). 하지만 도구는
   **다른 에이전트로 넘기는 것**(자기 로드아웃을 가진 하위 두뇌)일 수도, 파이프라인의 **다음 작업을
   트리거**하는 것일 수도 있다. 두뇌에겐 다 똑같다 — 잡을 수 있는 하나의 이름. 그래서 도구는 어떤
   땐 mechanics 위의 인터페이스이고, 어떤 땐 *다음 수*(다른 에이전트, 또는 다음 단계의 시작)다.
   `notify`는 알림만, `read_news`는 읽기만. 서로 모른다. 이들 전체가 **도구 창고**다.
2. **도구가 스스로를 설명한다.** `--describe` 한 줄이 "이 도구가 무엇인가"의 단일 출처다.
3. **`loadout` 조립기가 두뇌에 도구상자를 건넨다.** 도구 *이름* 목록(로드아웃)을 주면 그 자기서술을
   모아 출력한다. 루틴은 깰 때 이걸 실행해 *창고에서 자기 도구상자를 내려받는다*.
4. **스킬은 *미션만*.** 무엇을 할지 + 로드아웃 이름. 설명은 스킬이 재서술하지 않고 *도구상자와 함께*
   온다.
5. **두뇌가 스스로 생각한다 — 도구는 자동 연쇄가 아니다.** `notify`와 `publish_notion`은 따로 둔다.
   "노션에 쓰면 자동으로 알림"으로 묶지 않는다. 두 도구를 배관에서 융합하는 순간 정책이 굳어버려서,
   조용히 발행하거나 발행 없이 알림만 보내는 자유를 잃는다. 도구는 독립으로 두고, *두뇌가* 하나를
   부를지·다른 걸 부를지·둘 다 부를지 스스로 판단하게 한다. 생각은 두뇌의 몫이지, 배관이 미리 정할
   일이 아니다.

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

## 패턴의 한계

이것은 프레임워크가 아니라 패턴이고, 그게 정직한 한계다: **런타임에서 강제되는 것이 없다.** 베이스
클래스도, 제어 역전도, 루틴이 자기 로드아웃을 무시하거나 생 mechanics를 다시 inline하는 것을 *막는*
장치도 없다. 준수는 규율의 문제다 — 가드레일이 필요하면 스킬이 미션과 선언된 로드아웃을 갖는지
검사하는 CI 체크 하나. 대신 얻는 건 가벼움이다: 설치할 게 없고, 도구 하나·루틴 하나씩 점진적으로
도입하며, 스크립트와 프롬프트를 돌리는 어떤 스택에도 끼워진다.

## 왜 중요한가

다시 슈트로. 두뇌는 더 나은 모델로 갈아끼우면 업그레이드된다 — 그건 당신이 짜는 코드가 아니라
채택하는 모델이다. 당신의 일상적 엔지니어링은 장비로 간다 — 두뇌가 발견하고, 잡고, *사용하는 게
관측되는* 도구. 그리고 두뇌가 인터페이스(이름 붙은 도구들의 로드아웃)에 의존하므로 슈트는 모델
비종속적이다: 모델을 바꿔도 같은 로드아웃이 그대로 맞는다. 자기서술적이고 관측 가능한
도구상자(로드아웃)가 바로 두뇌가 *핸들을 잡는* 방식이다 — 깨어나 허용된 도구를 내려받고, 할 수 있는
걸 보고, 행동한다. 그리고 당신은 부작용으로 추측하는 게 아니라 인터페이스에서 그걸 지켜본다. 시스템은
가끔 모델을 부르는 프로그램이 아니라, 모델이 입는 슈트가 된다 — 어떤 유능한 모델이든.

## 레시피 (요약)

1. **도구** = 작은 스크립트, 능력 하나씩, mechanics 숨김 — 전체가 도구 창고. `--describe` + 경계
   로그(`INVOKED` + `OK/DRY/ERR`). 부작용 도구는 `DRY_RUN` 지원.
2. **로드아웃** = 한 루틴이 고른 도구들의 자기서술을 출력하는 조립기. 루틴이 깰 때 실행해 *도구상자를
   내려받음*.
3. **스킬** = 미션(판단) + 로드아웃 목록. mechanics 없음. 두뇌가 도구를 *조합*하게 하고, 배관에서
   자동 연쇄하지 마라.

실행 가능한 예시는 [`examples/`](examples/)에 있다.
