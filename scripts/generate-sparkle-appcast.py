#!/usr/bin/env python3
"""Sign dedicated-arch Sparkle 2 update zips and write an appcast.

Publish-only helper. The private Ed25519 seed is Sparkle's generate_keys -x
format (32-byte seed, base64). Pass it with -f/--ed-key-file (mode 600 temp
file). Never commit or print that key.

The generated feed lists dedicated arm64 and x86_64 zip enclosures for the same
version. Apple Silicon items carry sparkle:hardwareRequirements=arm64 so Intel
Macs skip them; the client also filters by macos-arm64 / macos-x86_64 filename.
Universal archives are ignored.
"""

from __future__ import annotations

import argparse
import base64
import os
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Iterable
from xml.sax.saxutils import escape

DATE_BUILD_RE = re.compile(
    r"^[0-9]{4}\.([1-9]|1[0-2])\.([1-9]|[12][0-9]|3[01])\.[1-9][0-9]*$"
)
DEDICATED_ARCHES = ("arm64", "x86_64")
ARCHIVE_NAME_RE = re.compile(
    r"^SyncthingTray-(?P<version>.+)-macos-(?P<arch>arm64|x86_64|universal)\.zip$"
)


class SparkleKeyError(ValueError):
    pass


def _signing_backend() -> tuple[str, Callable[[bytes, bytes], bytes], Callable[[bytes], bytes]]:
    """Return (name, sign(seed, data)->sig, public_from_seed(seed)->pub)."""
    try:
        from nacl.signing import SigningKey  # type: ignore

        def sign(seed: bytes, data: bytes) -> bytes:
            return bytes(SigningKey(seed).sign(data).signature)

        def public_from_seed(seed: bytes) -> bytes:
            return bytes(SigningKey(seed).verify_key)

        return "pynacl", sign, public_from_seed
    except ImportError:
        pass

    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import (  # type: ignore
            Ed25519PrivateKey,
        )

        def sign(seed: bytes, data: bytes) -> bytes:
            return Ed25519PrivateKey.from_private_bytes(seed).sign(data)

        def public_from_seed(seed: bytes) -> bytes:
            return (
                Ed25519PrivateKey.from_private_bytes(seed)
                .public_key()
                .public_bytes_raw()
            )

        return "cryptography", sign, public_from_seed
    except ImportError as exc:
        raise SparkleKeyError(
            "Signing Sparkle archives requires PyNaCl or cryptography "
            "(pip install pynacl)."
        ) from exc


def parse_private_seed(text: str) -> bytes:
    raw = text.strip()
    if not raw:
        raise SparkleKeyError("SPARKLE_ED_PRIVATE_KEY is empty.")

    if "BEGIN" in raw:
        try:
            from cryptography.hazmat.primitives.serialization import (
                load_pem_private_key,
            )
            from cryptography.hazmat.primitives.asymmetric.ed25519 import (
                Ed25519PrivateKey,
            )
        except ImportError as exc:
            raise SparkleKeyError(
                "PEM Sparkle keys require the cryptography package; "
                "prefer the base64 seed from Sparkle generate_keys."
            ) from exc
        key = load_pem_private_key(raw.encode("utf-8"), password=None)
        if not isinstance(key, Ed25519PrivateKey):
            raise SparkleKeyError("PEM is not an Ed25519 private key.")
        return key.private_bytes_raw()

    try:
        decoded = base64.b64decode(raw, validate=True)
    except Exception:
        try:
            decoded = base64.b64decode(raw)
        except Exception as exc:
            raise SparkleKeyError("Private key is not valid base64.") from exc

    if len(decoded) == 32:
        return decoded
    if len(decoded) == 64:
        return decoded[:32]
    raise SparkleKeyError(
        f"Unsupported Ed25519 private key length {len(decoded)} (expected 32-byte seed)."
    )


def load_private_seed(*, key_file: str | None = None) -> bytes:
    if key_file:
        path = Path(key_file)
        if not path.is_file():
            raise SparkleKeyError(f"EdDSA key file not found: {path}")
        return parse_private_seed(path.read_text(encoding="utf-8"))
    return parse_private_seed(os.environ.get("SPARKLE_ED_PRIVATE_KEY", ""))


def public_key_b64(seed: bytes) -> str:
    _, _, public_from_seed = _signing_backend()
    return base64.b64encode(public_from_seed(seed)).decode("ascii")


def sign_file(path: Path, seed: bytes) -> tuple[str, int]:
    data = path.read_bytes()
    _, sign, _ = _signing_backend()
    signature = sign(seed, data)
    if len(signature) != 64:
        raise SparkleKeyError(f"Ed25519 signature was {len(signature)} bytes, expected 64.")
    return base64.b64encode(signature).decode("ascii"), len(data)


def verify_signature(path: Path, signature_b64: str, public_b64: str) -> None:
    data = path.read_bytes()
    signature = base64.b64decode(signature_b64)
    public = base64.b64decode(public_b64)
    try:
        from nacl.signing import VerifyKey  # type: ignore

        VerifyKey(public).verify(data, signature)
        return
    except ImportError:
        pass
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import (  # type: ignore
            Ed25519PublicKey,
        )

        Ed25519PublicKey.from_public_bytes(public).verify(signature, data)
        return
    except ImportError as exc:
        raise SparkleKeyError("Install pynacl or cryptography to verify signatures.") from exc


def enclosure_url(repo: str, version: str, arch: str) -> str:
    name = f"SyncthingTray-{version}-macos-{arch}.zip"
    return f"https://github.com/{repo}/releases/download/v{version}/{name}"


def parse_archive_name(path: Path) -> tuple[str, str] | None:
    match = ARCHIVE_NAME_RE.fullmatch(path.name)
    if match is None:
        return None
    return match.group("version"), match.group("arch")


def collect_dedicated_archives(paths: Iterable[Path], version: str) -> dict[str, Path]:
    found: dict[str, Path] = {}
    for path in paths:
        parsed = parse_archive_name(path)
        if parsed is None:
            continue
        archive_version, arch = parsed
        if archive_version != version:
            continue
        if arch == "universal":
            continue
        found[arch] = path
    missing = [arch for arch in DEDICATED_ARCHES if arch not in found]
    if missing:
        raise SystemExit(
            "Sparkle appcast needs dedicated-arch zips; missing: "
            + ", ".join(f"SyncthingTray-{version}-macos-{arch}.zip" for arch in missing)
        )
    return found


def rfc822(now: datetime | None = None) -> str:
    stamp = now or datetime.now(timezone.utc)
    return stamp.strftime("%a, %d %b %Y %H:%M:%S +0000")


def render_appcast(
    *,
    version: str,
    repo: str,
    signatures: dict[str, tuple[str, int]],
    pub_date: str,
    minimum_system_version: str = "14.0",
) -> str:
    items: list[str] = []
    # arm64 first so equal-version Sparkle clients that skip hardware
    # filtering still prefer Apple Silicon when both items remain.
    for arch in DEDICATED_ARCHES:
        signature, length = signatures[arch]
        hardware = ""
        if arch == "arm64":
            hardware = "\n            <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>"
        items.append(
            f"""        <item>
            <title>Syncthing Tray {escape(version)} ({escape(arch)})</title>
            <pubDate>{escape(pub_date)}</pubDate>
            <link>https://github.com/{escape(repo)}/releases/tag/v{escape(version)}</link>
            <sparkle:version>{escape(version)}</sparkle:version>
            <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>{escape(minimum_system_version)}</sparkle:minimumSystemVersion>{hardware}
            <enclosure
                url="{escape(enclosure_url(repo, version, arch))}"
                sparkle:edSignature="{escape(signature)}"
                length="{length}"
                type="application/octet-stream" />
        </item>"""
        )
    joined = "\n".join(items)
    return f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Syncthing Tray</title>
        <link>https://github.com/{escape(repo)}</link>
        <description>Dedicated-arch Sparkle 2 updates for Syncthing Tray (macos-arm64 and macos-x86_64). Universal extras are not listed.</description>
        <language>en</language>
{joined}
    </channel>
</rss>
"""


def generate_appcast(
    *,
    version: str,
    repo: str,
    archive_paths: list[Path],
    output: Path,
    seed: bytes,
) -> None:
    if not DATE_BUILD_RE.fullmatch(version):
        raise SystemExit(f"Refusing to appcast non-release version {version}")
    archives = collect_dedicated_archives(archive_paths, version)
    signatures = {arch: sign_file(path, seed) for arch, path in archives.items()}
    xml = render_appcast(
        version=version,
        repo=repo,
        signatures=signatures,
        pub_date=rfc822(),
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(xml, encoding="utf-8")
    print(f"Wrote {output} (arm64 + x86_64 enclosures for {version})")


def self_test() -> None:
    _, sign, public_from_seed = _signing_backend()
    seed = os.urandom(32)
    public = base64.b64encode(public_from_seed(seed)).decode("ascii")
    assert public_key_b64(seed) == public
    assert len(base64.b64decode(public)) == 32

    pem_seed = parse_private_seed(base64.b64encode(seed).decode("ascii"))
    assert pem_seed == seed

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        version = "2026.8.28.1"
        files = {}
        for arch, payload in (
            ("arm64", b"arm64-dedicated-update-body"),
            ("x86_64", b"x86_64-dedicated-update-body"),
            ("universal", b"universal-must-be-ignored"),
        ):
            path = root / f"SyncthingTray-{version}-macos-{arch}.zip"
            path.write_bytes(payload)
            files[arch] = path

        data = files["arm64"].read_bytes()
        signature = sign(seed, data)
        assert len(signature) == 64
        verify_signature(
            files["arm64"],
            base64.b64encode(signature).decode("ascii"),
            public,
        )

        output = root / "appcast.xml"
        generate_appcast(
            version=version,
            repo="bstone108/Syncthing-Swift-Tray",
            archive_paths=list(files.values()),
            output=output,
            seed=seed,
        )
        xml = output.read_text(encoding="utf-8")
        assert "macos-arm64.zip" in xml
        assert "macos-x86_64.zip" in xml
        assert "macos-universal.zip" not in xml
        assert xml.index("macos-arm64.zip") < xml.index("macos-x86_64.zip")
        assert "<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>" in xml
        assert xml.count("<item>") == 2
        assert "sparkle:edSignature=" in xml
        assert f"releases/download/v{version}/SyncthingTray-{version}-macos-arm64.zip" in xml

        key_file = root / "eddsa_priv"
        key_file.write_text(base64.b64encode(seed).decode("ascii") + "\n", encoding="utf-8")
        key_file.chmod(0o600)
        assert load_private_seed(key_file=str(key_file)) == seed

        try:
            collect_dedicated_archives([files["universal"]], version)
        except SystemExit:
            pass
        else:
            raise AssertionError("universal-only inputs must fail")

    print("self-test passed")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument(
        "-f",
        "--ed-key-file",
        help="Sparkle generate_keys -x private seed file (preferred on publish).",
    )
    parser.add_argument(
        "--print-public-key",
        action="store_true",
        help="Print SUPublicEDKey derived from -f or SPARKLE_ED_PRIVATE_KEY.",
    )
    parser.add_argument("--version", help="date.build version (YYYY.M.D.N)")
    parser.add_argument(
        "--repo",
        default=os.environ.get("GH_REPO", "bstone108/Syncthing-Swift-Tray"),
        help="GitHub owner/repo for enclosure URLs",
    )
    parser.add_argument(
        "--output",
        default="appcast.xml",
        help="Appcast XML destination",
    )
    parser.add_argument(
        "archives",
        nargs="*",
        type=Path,
        help="Dedicated-arch zip paths (universal files are ignored)",
    )
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return 0

    try:
        seed = load_private_seed(key_file=args.ed_key_file)
        if args.print_public_key:
            print(public_key_b64(seed))
            return 0
        if not args.version or not args.archives:
            parser.error("--version and zip paths are required unless --self-test or --print-public-key")
        generate_appcast(
            version=args.version,
            repo=args.repo,
            archive_paths=args.archives,
            output=Path(args.output),
            seed=seed,
        )
        return 0
    except SparkleKeyError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
