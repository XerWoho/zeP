## **docs/CONFIG.md**

# zeP – Configuration Guide

zeP is designed to be zero-configuration for most projects.
However, some optional configuration options allow you to tweak behavior and environment settings.

---

## **Configuration File Location**

By default, zeP looks for project configuration in:

- zep.json
- zep.lock

---

## **Manifest File Example**

```json
{
  "author": "You",
  "tags": [],
  "zig_version": "0.15.2",
  "repo": "<repo>",
  "name": "project",
  "cmd": [
    {
      "name": "release_windows",
      "cmd": "zig build -Doptimize=ReleaseFast -freference-trace -Dtarget=x86_64-windows-msvc"
    }
  ],
  "description": "Great project",
  "version": "0.1",
  "license": "MIT",
  "packages": ["package@0.1.0"],
  "dev_packages": [],
  "build": {
    "entry": "/src/main.zig",
    "target": "x86_64-windows-msvc"
  }
}
```

---

## **Explanation of Fields**

- **name** – Project name
- **author** – Author of project (You)
- **version** – project version
- **zig_version** – The zig version of project
- **repo** – Target repository
- **tags** – Short tags matching the project
- **license** – License of project
- **description** – Description of project
- **build.target** – Target triple for Zig build
- **build.entry** – Entry of project
- **packages** – List of package@version to fetch
- **dev_packages** – Development packages (not configurated _yet_)
- **cmd** – Executeable commands

---

## **Advanced Options**

- `.zep/injector.zig` can be customized to inject extra imports if needed for advanced users.

---

## Notes

- zeP automatically resolves dependencies, downloads them if missing, and links existing ones.
- Configuration is optional; defaults work for most projects.
