## **docs/DOCS.md**

# zeP – Docs

zeP has multiple commands, that make your life easier. Most of
it is automated, simple, and clean.

---

### **Package Commands**

#### **Install a package**

```bash
zep install <package-name>@<version> (--inj)
```

- Looks in local registry
- Falls back to custom registry
- Suggests similar names if incorrect
- Updates hash & lockfile

#### **Uninstall a package**

```bash
zep uninstall <package-name>  # deletes from local project
```

```bash
zep global-uninstall <package-name>@<version>  # deletes globally
```

```bash
zep fglobal-uninstall <package-name>@<version>  # deletes globally forcefully
```

- Uninstalls package from local project
- Removes from manifest
- Deletes package if not used by any project

#### **Inject package modules**

```bash
zep inject
```

- Asks which modules should get packages injected

#### **Info of a package**

```bash
zep info <package-name>
```

- Returns information about package

#### **List package version**

```bash
zep pkg list <package-name>
```

- Lists available versions of said package
- Includes corresponding zig version

#### **Add a custom package**

```bash
zep pkg add <package-name>
```

(if a package is not included in zep.run, you can add your own! [unverified])

- Adds a custom package to customPackages

#### **Remove a custom package**

```bash
zep pkg remove <package-name>
```

- Removes a custom package

#### **Purge**

```bash
zep purge
```

- Purges the packages from the local project
- Executes uninstall for all packages installed

#### **Cache**

```bash
zep cache list
```

- Lists cached items

```bash
zep cache clean (package_name@package_version)
```

- Cleans the entire cache
- Or a given package

```bash
zep cache size
```

- Returns the size of the current cache
- From Bytes -> Terabytes

---

### **Custom Commands**

```bash
zep cmd add
```

- adds a custom command

```bash
zep cmd run <cmd>
```

- run custom command

```bash
zep cmd remove <cmd>
```

- removes custom command

```bash
zep cmd list
```

- lists all custom commands

---

### **Zig Version Commands**

#### **Install a Zig version**

```bash
zep zig install <version> <target>
```

- Target defaults back depending on system

#### **List installed Zig versions**

```bash
zep zig list
```

#### **Switch active Zig version**

```bash
zep zig switch <version> <target>
```

- Target defaults back depending on system

#### **Uninstall a Zig version**

```bash
zep zig uninstall <version>
```

### **Zep Commands**

#### **Install a zeP version**

```bash
zep zep install <version>
```

#### **List installed zeP versions**

```bash
zep zep list
```

#### **Switch zeP version** [DO NOT USE FOR zeP => (soft-lock)]

```bash
zep zep switch <version>
```

#### **Uninstall a zeP version**

```bash
zep zep uninstall <version>
```

---

### **Prune (zep/zig)**

```bash
zep zig prune
zep zep prune
```

- Prunes empty folders of zig or zep versions
- Only deletes if the folders have no files/folder in them

---

### **PreBuilt Commands**

#### **Build a preBuilt**

```bash
zep prebuilt build [name] (target)
```

- Builds a prebuilt with a given name (will overwrite if exists)
- Target falls back to ".", if not specified

#### **Use a preBuilt**

```bash
zep prebuilt use [name] (target)
```

- Uses a prebuilt (if exists)
- Target falls back to ".", if not specified

#### **Delete a preBuilt**

```bash
zep prebuilt delete [name]
```

- Deletes a prebuilt (if exists)

---

### **Build Commands**

```bash
zep build
```

- Runs build command

```bash
zep runner --target <target-exe> --args <args>
```

- Builds and runs your executeable, including the args

---

## **Configuration Files**

### **`zep.json`**

Your project’s declared dependencies.

### **`zep.lock`**

Exact versions, hashes, and metadata of installed packages.

Both are fully auto-managed. Direct editing is unnecessary unless you enjoy breaking things.

### **`.zep/.conf/injector.json`**

Stores the modules that currently include or exclude packages.

#### **Init project**

```bash
zep init
```

- Adds zep.json, zep.lock and .zep/ with starter values
- Inits own Zig project, with pre-set values

#### **zep.lock file**

```bash
zep lock
```

- Moves changed data from zep.json into zep.lock [root]

#### **zep.json file**

```bash
zep json
```

- Allows for modification of data within zep.json using terminal
- More reliable as changes will get automatically reflected onto .lock

#### **Doctor check**

```bash
zep doctor (--fix)
```

- Checks config files, detect issues
- Fixes issues automatically if told to
