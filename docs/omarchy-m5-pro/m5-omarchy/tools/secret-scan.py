#!/usr/bin/env python3
"""secret-scan.py DIR (env M5_KNOWN_SECRETS=comma list): stdlib secret/PII scan for the public journey repo (gitleaks-style rules + project list).
Prints file:line:rule:match for every hit; exit 1 if any hit is not in the ALLOW set. Read-only."""
import math, os, re, sys

RULES = {
    "private-key": r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    "ssh-pubkey": r"\bssh-(ed25519|rsa|dss) AAAA[0-9A-Za-z+/]{20,}",
    "github-token": r"\b(ghp|gho|ghu|ghs|ghr)_[0-9A-Za-z]{30,}|\bgithub_pat_[0-9A-Za-z_]{30,}",
    "aws-key": r"\b(AKIA|ASIA)[0-9A-Z]{16}\b",
    "slack-token": r"\bxox[abprs]-[0-9A-Za-z-]{10,}",
    "anthropic/openai-key": r"\bsk-(ant-)?[0-9A-Za-z_-]{20,}",
    "jwt": r"\beyJ[0-9A-Za-z_-]{10,}\.[0-9A-Za-z_-]{10,}\.[0-9A-Za-z_-]{10,}",
    "password-assign": r"(?i)\b(pass(word|wd)?|pwd|secret|api[_-]?key|token)\s*[:=]\s*['\"]?[^\s'\"<>]{6,}",
    "email": r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}",
    "tailscale-ip": r"\b100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.\d{1,3}\.\d{1,3}\b",
    "mac-address": r"\b([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}\b",
    "uuid": r"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b",
    "ecid": r"(?i)\becid\b\s*[:=]?\s*(0x)?[0-9a-f]{12,16}\b",
    "apple-serial": r"\b(C02|F[0-9A-Z]{2}|[A-Z0-9]{2}[0-9A-Z]{8})[0-9A-Z]{0,2}\b(?=.*(?i:serial))",
    "home-path": r"/home/[a-z0-9_-]+|/Users/[A-Za-z0-9_-]+",
}
# Known secrets and personal names come from the environment (never stored here): M5_KNOWN_SECRETS="s1,s2"
for _i, _s in enumerate(x for x in os.environ.get("M5_KNOWN_SECRETS", "").split(",") if x):
    RULES[f"known-secret-{_i}"] = re.escape(_s)
# Public, non-identifying values that are expected in this repo.
ALLOW = {
    "uuid": {"0FC63DAF-8483-4772-8E79-3D69D8477DE4", "C12A7328-F81F-11D2-BA4B-00A0C93EC93B",   # GPT Linux / EFI types
             "7C3457EF-0000-11AA-AA11-00306543ECAC", "69646961-6700-11AA-AA11-00306543ECAC",   # GPT Apple APFS / ISC
             "52637672-7900-11AA-AA11-00306543ECAC"},                                         # GPT Apple Recovery
    "email": {"noreply@anthropic.com", "david@gibson.dropbear.id.au", "getty@tty1.service",
              "pkgs@omarchy.org", "alpine-devel@lists.alpinelinux.org-616ae350.rsa.pub"},
}

def entropy(s):
    return -sum(s.count(c) / len(s) * math.log2(s.count(c) / len(s)) for c in set(s))

def main():
    root, bad = sys.argv[1], 0
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x != ".git"]
        for fn in files:
            p = os.path.join(d, fn)
            try:
                t = open(p, encoding="utf-8").read()
            except (UnicodeDecodeError, OSError):
                print(f"{p}:0:binary-or-unreadable:"); bad += 1; continue
            for n, line in enumerate(t.split("\n"), 1):
                for rule, rx in RULES.items():
                    for m in re.finditer(rx, line):
                        v = m.group(0)
                        if v.upper() in {a.upper() for a in ALLOW.get(rule, ())}:
                            continue
                        print(f"{os.path.relpath(p, root)}:{n}:{rule}:{v[:80]}"); bad += 1
                for tok in re.findall(r"[A-Za-z0-9+/=_-]{40,}", line):   # high-entropy blobs (gitleaks generic)
                    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", tok) and entropy(tok) > 4.5:
                        print(f"{os.path.relpath(p, root)}:{n}:high-entropy:{tok[:80]}"); bad += 1
    sys.exit(1 if bad else 0)

if __name__ == "__main__":
    main()
