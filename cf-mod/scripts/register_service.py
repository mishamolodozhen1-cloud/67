#!/usr/bin/env python3
"""Регистрирует OverlayService в manifest."""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NS = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", NS)

def main():
    path = Path(sys.argv[1])
    tree = ET.parse(path)
    root = tree.getroot()
    app = root.find("application")
    if app is None:
        raise SystemExit("no application")
    svc_name = "com.cf.overlay.OverlayService"
    if not any(s.attrib.get(f"{{{NS}}}name") == svc_name for s in app.findall("service")):
        svc = ET.SubElement(app, "service")
        svc.set(f"{{{NS}}}name", svc_name)
        svc.set(f"{{{NS}}}exported", "false")
    tree.write(path, xml_declaration=True, encoding="utf-8")
    print("[+] service registered")

if __name__ == "__main__":
    main()
