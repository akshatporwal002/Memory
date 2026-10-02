# Current UI captures

Each changed screen has its own folder. `current.png` is the latest checked simulator capture; `previous.png` is the immediately preceding capture. Older images are removed when a new capture is added.

After a UI change, run its simulator screenshot test, export the image, inspect it, then rotate it with:

```powershell
.\tooling\update-current-ui.ps1 -View Library -Image C:\path\to\exported.png
```

The view name can be `Today`, `Library`, `Deck`, or a new screen name. Keep capture names stable so later UI reviews can compare like for like.
