# Configure the canonical private Git remote

The reconstruction runtime did not have GitHub CLI (`gh`) and no remote URL is invented here.

Target: a **private** GitHub repository named `POSFlutter`.

## Windows / PowerShell

1. Create an empty **private** repository named `POSFlutter` in the intended GitHub account/organization. Do not initialize it with another README/history if you want to push this baseline directly.
2. Open PowerShell in the cloned/restored canonical repository.
3. Verify the local baseline first:

```powershell
git status
git log --oneline -5
git tag -n
git remote -v
```

4. Add the real private URL supplied by GitHub:

```powershell
git remote add origin <URL-PRIVADA>
```

Do not literally use `<URL-PRIVADA>`; replace it with the actual HTTPS or SSH Git URL.

5. Verify before push:

```powershell
git remote -v
git status
```

6. Push normally, without force:

```powershell
git push -u origin main
git push origin --tags
```

7. Verify:

```powershell
git status
git log --oneline -5
git remote -v
```

## Restore from the portable bundle

If the working copy is lost but `POSFlutter_CANONICAL.bundle` is available:

```powershell
git clone .\POSFlutter_CANONICAL.bundle POSFlutter
cd POSFlutter
git status
git log --oneline -5
git tag -n
```

Then add the real private remote and push using the commands above.

## Safety rules

Do not use `git push --force`, `git reset --hard`, or destructive cleaning simply to resolve divergence. Inspect the local/remote history first. After every logical phase: validate, commit, push if `origin` is configured, refresh the Git bundle, and create a clean ZIP checkpoint.


## Canonical remote now configured

The canonical private remote is `https://github.com/RafaelL13/POSFlutter.git` on branch `main`. The FASE 17 starting checkpoint is `ee1c8f78b0f6e446f75b0b1a5ce7af79010aea97`. Bundles and ZIP checkpoints belong outside the working tree.
