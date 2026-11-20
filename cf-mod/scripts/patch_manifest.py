#!/usr/bin/env python3
"""Добавляет SYSTEM_ALERT_WINDOW и extractNativeLibs=true."""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NS = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", NS)

def main():
    path = Path(sys.argv[1])
    tree = ET.parse(path)
    root = tree.getroot()
    need = {
        "android.permission.SYSTEM_ALERT_WINDOW",
        "android.permission.FOREGROUND_SERVICE",
        "android.permission.INTERNET",
    }
    have = {el.attrib.get(f"{{{NS}}}name") for el in root.findall("uses-permission")}
    for perm in need - have:
        el = ET.SubElement(root, "uses-permission")
        el.set(f"{{{NS}}}name", perm)
    app = root.find("application")
    if app is not None:
        app.set(f"{{{NS}}}extractNativeLibs", "true")
        app.set(f"{{{NS}}}debuggable", "false")
    tree.write(path, xml_declaration=True, encoding="utf-8")
    print("[+] manifest patched")

if __name__ == "__main__":
    main()
