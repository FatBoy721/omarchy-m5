#!/usr/bin/env python3
"""Minimal Alpine (APK v2) verifier, stdlib + openssl CLI only.

  apk-verify.py index KEY.pub APKINDEX.tar.gz      -> verify signature, print nothing on success
  apk-verify.py pkg   KEY.pub APKINDEX.tar.gz NAME FILE.apk -> verify index sig, control checksum (C:Q1...) and
                                                    the data stream's sha256 against .PKGINFO datahash
  apk-verify.py show  KEY.pub APKINDEX.tar.gz NAME

APK v2 files are concatenated gzip streams: [signature][control][data]. The signature (.SIGN.RSA.<key>)
is an RSA/SHA-1 signature over the raw bytes of the control gzip stream (for APKINDEX: over the index
stream). The index's C: field is "Q1" + base64(SHA-1 of the control gzip stream bytes).
"""
import base64, hashlib, io, subprocess, sys, tarfile, tempfile, zlib


def gzip_members(blob):
    """Split concatenated gzip streams; return list of raw member byte strings."""
    out, pos = [], 0
    while pos < len(blob):
        d = zlib.decompressobj(16 + zlib.MAX_WBITS)
        d.decompress(blob[pos:])
        end = len(blob) - len(d.unused_data)
        out.append(blob[pos:end])
        pos = end
    return out


def tar_files(member):
    with tarfile.open(fileobj=io.BytesIO(zlib.decompress(member, 16 + zlib.MAX_WBITS)), mode="r:") as t:
        return {m.name: t.extractfile(m).read() for m in t.getmembers() if m.isfile()}


def verify_sig(key, sig_member, signed_member):
    sig = [v for k, v in tar_files(sig_member).items() if k.startswith(".SIGN.RSA")]
    if len(sig) != 1:
        sys.exit("no single .SIGN.RSA entry")
    with tempfile.NamedTemporaryFile() as s, tempfile.NamedTemporaryFile() as d:
        s.write(sig[0]); s.flush(); d.write(signed_member); d.flush()
        r = subprocess.run(["openssl", "dgst", "-sha1", "-verify", key, "-signature", s.name, d.name],
                           capture_output=True, text=True)
    if r.returncode != 0 or "Verified OK" not in r.stdout:
        sys.exit("SIGNATURE FAILED: " + r.stdout + r.stderr)


def verified_index(key, index_path):
    """Return the APKINDEX text, parsed from exactly the member that the signature covers."""
    m = gzip_members(open(index_path, "rb").read())
    if len(m) != 2:
        sys.exit(f"unexpected APKINDEX layout: {len(m)} gzip members")
    verify_sig(key, m[0], m[1])
    return tar_files(m[1])["APKINDEX"].decode()


def index_entries(key, index_path):
    text = verified_index(key, index_path)
    for block in text.strip().split("\n\n"):
        yield dict(l.split(":", 1) for l in block.splitlines() if ":" in l)


def main():
    if sys.argv[1] == "index":
        key, path = sys.argv[2:4]
        verified_index(key, path)
        print(f"index OK: {path}")
    elif sys.argv[1] == "pkg":
        key, index, name, apk = sys.argv[2:6]
        e = next(e for e in index_entries(key, index) if e["P"] == name)
        m = gzip_members(open(apk, "rb").read())
        if len(m) != 3:
            sys.exit(f"unexpected apk layout {apk}: {len(m)} gzip members")
        # 1) control stream is pinned by the signed index
        got = "Q1" + base64.b64encode(hashlib.sha1(m[1]).digest()).decode()
        if got != e["C"]:
            sys.exit(f"CHECKSUM MISMATCH {apk}: index {e['C']} file {got}")
        # 2) data stream is pinned by datahash (sha256) inside the verified control stream
        pkginfo = tar_files(m[1])[".PKGINFO"].decode()
        dh = [l.split("=", 1)[1].strip() for l in pkginfo.splitlines() if l.startswith("datahash")]
        if len(dh) != 1 or hashlib.sha256(m[2]).hexdigest() != dh[0]:
            sys.exit(f"DATAHASH MISMATCH {apk}")
        print(f"pkg OK: {name}-{e['V']} {e['C']} datahash {dh[0][:16]}…")
    elif sys.argv[1] == "show":
        key, index, name = sys.argv[2:5]
        e = next(e for e in index_entries(key, index) if e["P"] == name)
        print(e["V"], e.get("D", ""))


if __name__ == "__main__":
    main()
