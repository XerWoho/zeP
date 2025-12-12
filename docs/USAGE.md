## **docs/USAGE.md**

# zeP – Usage Guide

zeP is a fast, minimalist package and version manager for Zig.  
It provides easy bootstrapping, dependency management, and running of Zig projects.

---

## Installing zeP

### **Windows (PowerShell, as Administrator)**

```powershell
& ([scriptblock]::Create((New-Object Net.WebClient).DownloadString('https://zep.run/installer/installer.ps1')))
```

### **Linux**

```bash
curl -fsSL https://zep.run/installer/installer.sh | bash
```

### **AUR**

```bash
yay -S zep-bin
```

### **macOS**

```bash
brew tap XerWoho/homebrew-zep
brew install zep
```

---

## Bootstrap a Project

`zep bootstrap` prepares a new project or sets up an existing one with dependencies.

### **Syntax**

```bash
zep bootstrap --zig <zig_version> --deps "<package1@version,package2@version,...>"
```

### **Options**

| Option   | Description                                                                                                     |
| -------- | --------------------------------------------------------------------------------------------------------------- |
| `--zig`  | The target Zig version for the project. Installs it if not present, or switches if installed.                   |
| `--deps` | Comma-separated list of dependencies with versions. Installs and imports missing packages, links existing ones. |

---

## Running Projects

`zep runner` builds and executes your project using the configured dependencies.
Zig build is run under the hood, and the runner automatically finds the latest build.

### **Syntax**

```bash
zep runner
```

You can optionally pass arguments to the executed program:

```bash
zep runner --target <target-exe> --args <arg1> <arg2> ...
```

---

## CLI Reference

### `bootstrap`

- Sets up project with a specific Zig version and dependencies.
- Example:

```bash
zep bootstrap --zig 0.14.0 --deps "clap@0.10.0,zeit@0.7.0"
```

### `runner`

- Builds and runs the current project.
- Example:

```bash
zep runner
```

---

## Notes

- zeP automatically manages project-specific dependencies under `.zep/`.
- Versions prior to 0.5 were MIT licensed; starting 0.5, the project uses GPLv3.
