---
title: "OneNote zu Obsidian mit der Graph Api"
date: 2023-12-23T16:36:03+01:00
draft: true
tags:
  - Azure
  - Entra
  - PowerShell
  - Microsoft Graph
  - OneNote
  - Obsidian
  - Knowledge Management
categories:
  - dev
---

Durch eine Verkettung sonderbarer Zwischenfälle kam ich mal
wieder auf die Idee, meinen OneNote-Content in ein offenes
Format zu bringen. Da ich schon eine Weile Obsidian zum Wissensmanagement
nutze, lag Markdown als Zielformat nah.

Eine kurze Suche im Internet ergab nichts besonderes, außer viel
Herumgehampel mit pandoc und sehr viel manuellen Nacharbeiten. Unschön.
Und in dem Moment fiel mir wieder ein, dass mein Kollege 
[Friedrich Weinmann](https://github.com/friedrichweinmann/minigraph) mit seine
PowerShell-Modul MiniGraph bereits den nervigen Teil meiner Idee erledigt
hatte: Authentifizierung mit Entra!

## Vorbereitungen in Entra ID

App anlegen, screenshot, multitenant

### Delegated Permissions versus Application Permissions

Nein, technische Begriffe übersetze ich nicht. Wenn euer Azure-Portal auf
Deutsch eingestellt ist, habe ich großes Mitleid und ein wenig Unverständnis. Dennoch
sollten wir die beiden Begrifflichkeiten klären, um mit eventuellen Missverständnissen
aufzuräumen.

## Authentifizierung mit MiniGraph - Device Code Flow

Screentshot, Delegated und App

## Es geht ans Eingemachte: Befreiung der OneNotes!

liste alle notebooks (eigener ordner)
für alle notebooks liste alle sections (unterordner)
für alle sections, lise alle pages (unterordner)
für alle pages liste alle subpages (rekursion, unterordner)
Page Content -- Markdown.
Embedded images? Mal schauen