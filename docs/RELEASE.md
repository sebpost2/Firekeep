# Release Checklist

How to cut a new release of this project. There is no automation script for
this - it's a short enough process to run by hand, and automating a release
cadence that doesn't exist yet would be premature.

1. Run the full test suite and confirm everything is green:
   ```
   powershell.exe -NoProfile -Command "Invoke-Pester tests/"
   ```
2. Update `VERSION` (repo root, single line, e.g. `1.0.1`) to the new version.
3. Add a new entry at the top of `CHANGELOG.md` under `## [X.Y.Z] - YYYY-MM-DD`
   summarizing what changed since the last release.
4. Commit both files:
   ```
   git add VERSION CHANGELOG.md
   git commit -m "chore: release vX.Y.Z"
   ```
5. Tag the release:
   ```
   git tag vX.Y.Z
   ```
6. Build the release zip:
   ```
   powershell.exe -NoProfile -File _shared\scripts\package-release.ps1
   ```
7. Spot-check the zip: unzip it somewhere else, confirm `Start.bat` is
   present, and confirm no server-instance data, Java runtime, or playit
   secrets leaked in (they shouldn't - `package-release.ps1` uses an
   explicit allow-list - but check once per release anyway).
8. Hand off the zip to the client / wherever it's distributed.
