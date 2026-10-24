#!/usr/bin/env python3
"""Builds a pull request's review page: the steps of its How to verify?
section exactly as GitHub holds them, its screenshots embedded, and the
review's own results, findings and added steps from an optional overlay.

usage: build.py <owner/repo#n> [--out page.html] [--review overlay.json]

Without --out the page goes to .reviews/<repo>-<n>.html in the checkout the
command runs in, a folder this adds to the checkout's .git/info/exclude so
git never sees it.

The overlay is JSON:
  {"results": [{"name": "...", "outcome": "pass|fail|skip", "detail": "..."}],
   "findings": [{"severity": "high|medium|low", "title": "...", "body": "...",
                 "step": "<step id>"}],
   "added_steps": [{"after": "<step id, or empty for before the first>",
                    "title": "...", "body": "..."}],
   "missed": "..."}
Bodies are Markdown in the form the pull-requests skill writes. Step ids are
the section's slug and the step's number, such as setup-2; build.py prints
them.

Run it with python3 -I. It needs the gh CLI signed in to the PR's host.
"""

import base64
import hashlib
import html
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.expanduser("~/.claude/drafts/review-page-images")
IMAGE_TYPES = ("image/png", "image/jpeg", "image/gif", "image/webp")


def gh_json(*args):
    out = subprocess.run(["gh", *args], check=True, capture_output=True, text=True)
    return json.loads(out.stdout)


def fetch_image(url):
    """The image as a data URI, or None when it is no image, such as a video."""
    os.makedirs(CACHE, exist_ok=True)
    key = hashlib.sha256(url.encode()).hexdigest()[:32]
    meta_path = os.path.join(CACHE, key + ".type")
    body_path = os.path.join(CACHE, key + ".bin")
    if not os.path.exists(body_path):
        token = subprocess.run(
            ["gh", "auth", "token"], check=True, capture_output=True, text=True
        ).stdout.strip()
        # Private attachments answer only with the token, then redirect to a
        # signed storage address that refuses one. curl drops the header when
        # the redirect changes host; urllib would carry it along.
        result = subprocess.run(
            ["curl", "-sSfL", "-H", "@-", "-H", "Accept: application/octet-stream",
             "-o", body_path, "-w", "%{content_type}", url],
            input="Authorization: Bearer %s\n" % token,
            check=True, capture_output=True, text=True,
        )
        with open(meta_path, "w") as f:
            f.write(result.stdout.split(";")[0].strip())
    with open(meta_path) as f:
        content_type = f.read().strip()
    if content_type not in IMAGE_TYPES:
        return None
    with open(body_path, "rb") as f:
        return "data:%s;base64,%s" % (content_type, base64.b64encode(f.read()).decode())


def slug(text):
    text = re.sub(r"[^\w\s-]", "", text.lower(), flags=re.UNICODE)
    return re.sub(r"[\s_]+", "-", text).strip("-") or "steps"


CODE_SPAN = re.compile(r"`([^`]+)`")
BOLD = re.compile(r"\*\*(.+?)\*\*")
LINK = re.compile(r"\[([^\]]+)\]\((https?://[^)\s]+)\)")
AUTOLINK = re.compile(r"<(https?://[^>\s]+)>")


def inline(text):
    spans = []

    def keep(match):
        spans.append("<code>%s</code>" % html.escape(match.group(1)))
        return "\x00%d\x00" % (len(spans) - 1)

    text = CODE_SPAN.sub(keep, text)
    text = html.escape(text, quote=False)
    text = BOLD.sub(r"<strong>\1</strong>", text)
    text = LINK.sub(r'<a href="\2" target="_blank" rel="noopener">\1</a>', text)
    text = AUTOLINK.sub(r'<a href="\1" target="_blank" rel="noopener">\1</a>', text)
    return re.sub("\x00(\\d+)\x00", lambda m: spans[int(m.group(1))], text)


IMG_TAG = re.compile(r"<img\b[^>]*>", re.I)
ATTR = re.compile(r'(\w+)="([^"]*)"')
ATTACHMENT = re.compile(r"^https://github\.com/user-attachments/\S+$")


def render_image(tag):
    attrs = dict(ATTR.findall(tag))
    src = attrs.get("src", "")
    alt = attrs.get("alt", "")
    data = fetch_image(src) if src.startswith("https://") else None
    if not data:
        return '<p><a href="%s" target="_blank" rel="noopener">%s</a></p>' % (
            html.escape(src),
            html.escape(alt or "Attachment on GitHub"),
        )
    return (
        '<figure class="shot"><button type="button" class="zoom" aria-label="Enlarge %s">'
        '<img src="%s" alt="%s" loading="lazy"></button></figure>'
        % (html.escape(alt or "screenshot"), data, html.escape(alt))
    )


def render_blocks(lines):
    """Markdown lines, already dedented, to HTML: paragraphs, lists, fenced
    blocks with a copy button, pictures and bare attachment links."""
    out = []
    para = []
    items = []

    def flush():
        if para:
            out.append("<p>%s</p>" % inline(" ".join(para)))
            para.clear()
        if items:
            out.append("<ul>%s</ul>" % "".join("<li>%s</li>" % inline(i) for i in items))
            items.clear()

    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        fence = re.match(r"^```(\w*)\s*$", stripped)
        if fence:
            flush()
            lang = fence.group(1) or "text"
            code = []
            i += 1
            while i < len(lines) and lines[i].strip() != "```":
                code.append(lines[i])
                i += 1
            body = "\n".join(code)
            if lang == "text" and re.fullmatch(r"https?://\S+", body.strip()):
                # An address to open: a link the reader clicks, and still copies.
                url = html.escape(body.strip())
                out.append(
                    '<div class="block" data-lang="address"><div class="block-bar"><span>address</span>'
                    '<button type="button" class="copy">Copy</button></div>'
                    '<pre><code><a href="%s" target="_blank" rel="noopener">%s</a></code></pre></div>'
                    % (url, url)
                )
                i += 1
                continue
            out.append(
                '<div class="block" data-lang="%s"><div class="block-bar"><span>%s</span>'
                '<button type="button" class="copy">Copy</button></div>'
                "<pre><code>%s</code></pre></div>"
                % (html.escape(lang), html.escape(lang), html.escape(body))
            )
        elif IMG_TAG.fullmatch(stripped):
            flush()
            out.append(render_image(stripped))
        elif ATTACHMENT.match(stripped):
            flush()
            out.append(render_image('<img src="%s" alt="Recording on GitHub">' % stripped))
        elif not stripped:
            flush()
        elif re.match(r"^[-*] ", stripped):
            if para:
                flush()
            items.append(stripped[2:])
        elif items and line.startswith("  "):
            items[-1] += " " + stripped
        else:
            if items:
                flush()
            para.append(stripped)
        i += 1
    flush()
    return "".join(out)


def dedent(lines):
    widths = [len(l) - len(l.lstrip(" ")) for l in lines if l.strip()]
    cut = min(widths) if widths else 0
    return [l[cut:] if len(l) >= cut else l.lstrip(" ") for l in lines]


def parse_verify(body):
    """Sections of the How to verify? part, each with its note and steps."""
    body = re.sub(r"<!--.*?-->", "", body.replace("\r\n", "\n"), flags=re.S)
    match = re.search(r"^##\s+[^\n]*how to verify[^\n]*$", body, re.I | re.M)
    if not match:
        return []
    rest = body[match.end():]
    end = re.search(r"^##\s", rest, re.M)
    part = rest[: end.start()] if end else rest

    sections = []
    current = {"title": "Steps", "note": [], "steps": []}

    def close():
        if current["steps"] or any(line.strip() for line in current["note"]):
            sections.append(dict(current))

    in_fence = False
    for line in part.split("\n"):
        if line.strip().startswith("```"):
            in_fence = not in_fence
        heading = None if in_fence else re.match(r"^###+\s+(.*)$", line)
        number = None if in_fence else re.match(r"^(\d+)\.\s+(.*)$", line)
        if heading:
            close()
            current = {"title": heading.group(1).strip(), "note": [], "steps": []}
        elif number:
            current["steps"].append({"n": int(number.group(1)), "first": number.group(2), "lines": []})
        elif current["steps"]:
            current["steps"][-1]["lines"].append(line)
        else:
            current["note"].append(line)
    close()

    used = set()
    result = []
    for section in sections:
        base = slug(section["title"])
        while base in used:
            base += "-x"
        used.add(base)
        steps = []
        for step in section["steps"]:
            lines = step["lines"]
            while lines and not lines[-1].strip():
                lines.pop()
            steps.append(
                {
                    "id": "%s-%d" % (base, step["n"]),
                    "n": step["n"],
                    "title": inline(step["first"]),
                    "body": render_blocks(dedent(lines)),
                }
            )
        result.append(
            {"title": section["title"], "note": render_blocks(dedent(section["note"])), "steps": steps}
        )
    return result


def add_review_steps(sections, review):
    for k, extra in enumerate(review.get("added_steps", []), 1):
        if not extra.get("after"):
            # Before the PR's first step, such as command steps the PR lacks.
            sections.insert(0, {"title": "Added by the review", "note": "", "steps": []})
            sections[0]["steps"].append(
                {
                    "id": "review-%d" % k,
                    "n": None,
                    "title": inline(extra["title"]),
                    "body": render_blocks(extra.get("body", "").split("\n")),
                    "added": True,
                }
            )
            if len(sections) > 1 and sections[1]["title"] == "Added by the review":
                sections[0]["steps"] = sections[1]["steps"] + sections[0]["steps"]
                del sections[1]
            continue
        for section in sections:
            ids = [s["id"] for s in section["steps"]]
            if extra["after"] in ids:
                at = ids.index(extra["after"]) + 1
                section["steps"].insert(
                    at,
                    {
                        "id": "%s-review-%d" % (extra["after"], k),
                        "n": None,
                        "title": inline(extra["title"]),
                        "body": render_blocks(extra.get("body", "").split("\n")),
                        "added": True,
                    },
                )
                break
        else:
            sys.exit("added step %d: no step %s" % (k, extra["after"]))


def render_review(review):
    if not review:
        return ""
    parts = []
    results = review.get("results", [])
    if results:
        rows = "".join(
            '<li class="result %s"><span class="pill">%s</span><span class="result-name">%s</span>'
            '<span class="result-detail">%s</span></li>'
            % (
                html.escape(r["outcome"]),
                html.escape({"pass": "Passed", "fail": "Failed", "skip": "Not run"}.get(r["outcome"], r["outcome"])),
                inline(r["name"]),
                inline(r.get("detail", "")),
            )
            for r in results
        )
        parts.append('<ul class="results">%s</ul>' % rows)
    findings = review.get("findings", [])
    if findings:
        items = "".join(
            '<li class="finding %s"><div class="finding-head"><span class="sev">%s</span>'
            '<span class="finding-title">%d. %s</span>%s</div>%s</li>'
            % (
                html.escape(f["severity"]),
                html.escape(f["severity"].capitalize()),
                n,
                inline(f["title"]),
                '<a class="to-step" href="#%s" data-step="%s">Step</a>' % (f["step"], f["step"]) if f.get("step") else "",
                render_blocks(f.get("body", "").split("\n")),
            )
            for n, f in enumerate(findings, 1)
        )
        parts.append('<h3 class="sub">Findings</h3><ol class="findings">%s</ol>' % items)
    elif results:
        parts.append('<p class="quiet">No findings.</p>')
    if review.get("missed"):
        parts.append(
            '<h3 class="sub">What the PR\'s steps missed</h3>%s'
            % render_blocks(review["missed"].split("\n"))
        )
    failed = sum(1 for r in results if r["outcome"] == "fail")
    passed = sum(1 for r in results if r["outcome"] == "pass")
    bits = []
    if results:
        bits.append("%d failed" % failed if failed else "%d of %d checks passed" % (passed, len(results)))
    if findings:
        by = {}
        for f in findings:
            by[f["severity"]] = by.get(f["severity"], 0) + 1
        bits.append(
            "%d finding%s: %s" % (
                len(findings), "" if len(findings) == 1 else "s",
                ", ".join("%d %s" % (by[k], k) for k in ("high", "medium", "low") if k in by),
            )
        )
    return (
        '<section class="review" aria-labelledby="review-h"><h2 id="review-h">Review</h2>'
        '<p class="review-sum">%s</p>%s</section>' % (html.escape(" · ".join(bits)), "".join(parts))
    )


def render_sections(sections):
    out = []
    for section in sections:
        steps = []
        for step in section["steps"]:
            label = "Added by the review" if step.get("added") else "Step %d" % step["n"]
            steps.append(
                '<li class="step%s" id="%s" data-id="%s" tabindex="-1">'
                '<button type="button" class="check" role="checkbox" aria-checked="false" aria-label="Done: %s"></button>'
                '<div class="step-main"><div class="step-label">%s</div><div class="step-title">%s</div>'
                '<div class="step-body">%s</div></div></li>'
                % (
                    " added" if step.get("added") else "",
                    step["id"],
                    step["id"],
                    html.escape(re.sub("<[^>]+>", "", step["title"])),
                    label,
                    step["title"],
                    step["body"],
                )
            )
        out.append(
            '<section class="group"><h2>%s</h2>%s<ol class="steps">%s</ol></section>'
            % (html.escape(section["title"]), '<div class="note">%s</div>' % section["note"] if section["note"] else "", "".join(steps))
        )
    return "".join(out)


def default_out(name, number):
    top = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], check=True, capture_output=True, text=True
    ).stdout.strip()
    common = subprocess.run(
        ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    exclude = os.path.join(common, "info", "exclude")
    os.makedirs(os.path.dirname(exclude), exist_ok=True)
    lines = open(exclude).read().split("\n") if os.path.exists(exclude) else []
    if "/.reviews/" not in lines:
        with open(exclude, "a") as f:
            f.write(("" if not lines or lines[-1] == "" else "\n") + "/.reviews/\n")
    os.makedirs(os.path.join(top, ".reviews"), exist_ok=True)
    return os.path.join(top, ".reviews", "%s-%s.html" % (name, number))


def take(args, flag):
    if flag not in args:
        return None
    at = args.index(flag)
    value = args[at + 1]
    del args[at : at + 2]
    return value


def main():
    args = sys.argv[1:]
    review_path = take(args, "--review")
    out_path = take(args, "--out")
    review = {}
    if review_path:
        with open(review_path) as f:
            review = json.load(f)
    if len(args) != 1 or "#" not in args[0]:
        sys.exit(__doc__)
    repo, number = args[0].split("#")

    pr = gh_json(
        "pr", "view", number, "--repo", repo,
        "--json", "title,url,body,headRefName,baseRefName,headRefOid,author,updatedAt,isDraft",
    )
    sections = parse_verify(pr["body"])
    if not sections:
        sys.exit("%s#%s has no How to verify? section" % (repo, number))
    if review:
        add_review_steps(sections, review)

    with open(os.path.join(HERE, "template.html")) as f:
        page = f.read()
    name = repo.split("/")[-1]
    out_path = out_path or default_out(name, number)
    fields = {
        "TITLE": html.escape("%s #%s review" % (name, number)),
        "PR_TITLE": inline(pr["title"]),
        "PR_URL": html.escape(pr["url"]),
        "PR_REF": html.escape("%s#%s" % (repo, number)),
        "BRANCH": html.escape("%s into %s" % (pr["headRefName"], pr["baseRefName"])),
        "HEAD": html.escape(pr["headRefOid"][:7]),
        "AUTHOR": html.escape(pr["author"]["login"]),
        "BUILT": datetime.now(timezone.utc).astimezone().strftime("%-d.%-m.%Y %H.%M"),
        "REVIEW": render_review(review),
        "SECTIONS": render_sections(sections),
        "STORAGE_KEY": html.escape("review:%s#%s" % (repo, number)),
    }
    for key, value in fields.items():
        page = page.replace("{{%s}}" % key, value)
    with open(out_path, "w") as f:
        f.write(page)
    for section in sections:
        print(section["title"] + ": " + ", ".join(s["id"] for s in section["steps"]))
    print("wrote %s (%d kB)" % (out_path, os.path.getsize(out_path) // 1024))


if __name__ == "__main__":
    main()
