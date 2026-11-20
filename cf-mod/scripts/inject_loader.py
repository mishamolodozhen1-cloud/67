#!/usr/bin/env python3
"""Инжектит System.loadLibrary("cfcheat") в <clinit> главной Application смали."""
import os, re, sys
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID_NS = "{http://schemas.android.com/apk/res/android}"

def find_application_class(manifest: Path) -> str:
    tree = ET.parse(manifest)
    app = tree.getroot().find("application")
    if app is None:
        raise SystemExit("[!] no <application> in manifest")
    name = app.attrib.get(f"{ANDROID_NS}name")
    if not name:
        return "android/app/Application"
    if name.startswith("."):
        pkg = tree.getroot().attrib.get("package", "")
        name = pkg + name
    return name.replace(".", "/")

def resolve_smali_path(unpack: Path, cls: str) -> Path:
    for smali_dir in sorted(unpack.glob("smali*")):
        p = smali_dir / f"{cls}.smali"
        if p.exists():
            return p
    target = unpack / "smali" / f"{cls}.smali"
    target.parent.mkdir(parents=True, exist_ok=True)
    stub = f""".class public L{cls};
.super Landroid/app/Application;

.method public constructor <init>()V
    .locals 0
    invoke-direct {{p0}}, Landroid/app/Application;-><init>()V
    return-void
.end method

.method static constructor <clinit>()V
    .locals 1
    const-string v0, "cfcheat"
    invoke-static {{v0}}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V
    return-void
.end method
"""
    target.write_text(stub)
    return target

def inject(smali: Path):
    src = smali.read_text()
    load = (
        '\n    const-string v0, "cfcheat"\n'
        '    invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V\n'
    )
    if "cfcheat" in src:
        return
    m = re.search(r"\.method\s+static\s+constructor\s+<clinit>\(\)V.*?\n", src)
    if m:
        insert = m.end()
        src = src[:insert] + "    .locals 1\n" + load + src[insert:]
        src = re.sub(r"(\.locals 1\n){2,}", ".locals 1\n", src, count=1)
    else:
        src += (
            "\n.method static constructor <clinit>()V\n"
            "    .locals 1\n"
            f"{load}"
            "    return-void\n"
            ".end method\n"
        )
    smali.write_text(src)

def main():
    unpack = Path(sys.argv[1])
    cls = find_application_class(unpack / "AndroidManifest.xml")
    smali = resolve_smali_path(unpack, cls)
    inject(smali)
    print(f"[+] loader injected into {smali}")

if __name__ == "__main__":
    main()
