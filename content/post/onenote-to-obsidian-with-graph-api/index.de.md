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

# Befreit OneNote! ✊

Durch eine Verkettung sonderbarer Zwischenfälle kam ich mal
wieder auf die Idee, meinen OneNote-Content in ein offenes
Format zu bringen. Da ich schon eine Weile Obsidian zum Wissensmanagement
nutze, lag Markdown als Zielformat nah.

Eine kurze Suche im Internet ergab nichts besonderes, außer viel
Herumgehampel mit pandoc und sehr viel manuellen Nacharbeiten. Unschön. Dabei
wollte ich eigentlich was nettes mit der Graph API (<https://learn.microsoft.com/en-us/graph/overview>).

>**Graph API? Watt is datt dann?**  
>Bei der Graph API handelt es sich
>um eine Programmierschnittstelle für Microsoft 365 und Entra ID (vormals Azure Active Directory)
>mit derer Hilfe sämtliche administrativen Arbeiten automatisiert
>werden können.  
>Der Zugriff auf Graph erfolgt mit Hilfe einer App Registration in Entra ID.

Und in dem Moment fiel mir wieder ein, dass mein Kollege 
[Friedrich Weinmann](https://github.com/friedrichweinmann/minigraph) mit seinem
PowerShell-Modul MiniGraph bereits den nervigen Teil meiner Idee erledigt
hatte: Authentifizierung mit Entra!

## Vorbereitungen in Entra ID

Um auf die Graph API zugreifen zu können, wird eine Resource benötigt, die
die gewünschten Berechtigungen beschreibt - eine App Registration, aus der später
unter Umständen eine Enterprise App wird.

![Screenshot showing the multi-tenant app usage enabled](./app_reg_multitenant.png)

Um auch für eure persönlichen OneNotes einen Export zu ermöglichen,
sollte die App Registration Multi-Tenant-fähig sein. Ist sie dies nicht,
müsst ihr alle Nutzer der App als Gastnutzer in euren Tenant einladen. Eine Nutzung
im Kontext der privaten Microsoft-Konten ist dann nicht möglich.

Zu letzt sollten noch die Graph-Berechtigungen eurer neuen App als
Delegated Permissions eingetragen werden. Um OneNote zu befreien, genügen
notes.read.all.

![Screenshot of delegated permissions to access OneNote notebooks](./app_reg_delegated.png)

### Delegated Permissions versus Application Permissions

Nein, technische Begriffe übersetze ich nicht. Wenn euer Azure-Portal auf
Deutsch eingestellt ist, habe ich großes Mitleid und ein wenig Unverständnis. Dennoch
sollten wir die beiden Begrifflichkeiten klären, um mit eventuellen Missverständnissen
aufzuräumen.

Delegated Permissions beschreiben Berechtigungen auf Ressourcen, auf die
die Anwenderin bereits Zugriff hat. Wird beispielsweise die relativ hohe Berechtigung
User.Read.All vergeben, bedeutet es nicht, dass alle User ausgelesen werden können.

Ebenso bedeutet die Berechtigung notes.read.all nur, dass die Anwenderin ihre und
für sie freigegebene OneNotes lesen kann.

In der alten Welt des On-Premises Active Directory wäre das vergleichbar mit Impersonation.
Ein Account handelt im Namen eines anderen Accounts.

Application Permissions beschreiben Berechtigungen der App Registration selbst,
im Kontext ebendieser! Eine Berechtigung User.Read.All kann hier weitreichenden Zugriff
zur Folge haben.

## Authentifizierung mit MiniGraph - Device Code Flow

Bevor wir uns den Graph-Calls widmen können, vielleicht einige, wenige Worte zu MiniGraph.

Fred hat mit diesem Modul einen schlanken, schnellen Weg zur Graph API
gebaut, mit allen erdenklichen Authentifizierungsmethoden. Diese hängen stark
von eurer App Registration und Nutzung ab: Credentials und Zertifikate werden
als App Secrets hinterlegt und zur Anmeldung im Kontext der App genutzt. Nicht ideal,
um das eigene OneNote aufzuräumen.

Abhilfe schaffen Connect-GraphBrowser beziehungsweise Connect-GraphDeviceCode. Beide
Authentifizierungs-Abläufe benötigen eine Client ID und eine Tenant ID. Moment mal,
ist die Tenant ID nicht üblicherweise etwas, was einzigartig pro Entra Tenant ist und
nicht öffentlich kommuniziert wird? Wie kann damit denn ein persönliches OneNote
abgefragt werden? Tja! In der Graph Doku gibt es die Antwort - 
mit der Tenant ID Common geht es hier weiter.

Die Client ID der App Registration müsst ihr euren Anwenderinnen jedoch mitteilen, bzw. 
die Client ID fest in eurer App Config (C#) oder PowerShell config (PSFramework) konfigurieren.
Bei der Anmeldung wird bei der Nutzung ein Disclaimer eingeblendet, der die detaillierten
Berechtigungen eurer App anzeigt und eine Zustimmung der Anwenderin erfordert.

## Es geht ans Eingemachte: Befreiung der OneNotes!

Die Anforderungen an unseren kleinen Exporter sind nicht umfangreich:
- 1-n Notebooks oder alle Notebooks abrufen
- In einen Output-Ordner werden pro Notebook und Sektion Unterordner angelegt
- Pro Page wird eine Markdown-Datei erstellt
- Eingebettete Bilder werden heruntergeladen und in einen Unterorder resources abgelegt und verlinkt

Aus diesen Informationen können wir schon mal die Parameter erzeugen. Einige sinnvolle
Standardwerte wie Tenant ID und Client ID, und schon ist das Cmdlet fertig. Die User ID me
bezeichnet die aktuelle Anwenderin. Der Code kann jedoch auch für andere
Accounts genutzt werden, indem beispielsweise dem Parameter User der string `user/GUID DES USERS/`
übergeben wird.

```powershell
[CmdletBinding(DefaultParameterSetName = 'All')]
param
(
    [Parameter(ParameterSetName = 'Notebook')]
    [Parameter(ParameterSetName = 'All')]
    [string]
    $TenantId = 'Common',

    # Use mine or create your own
    [Parameter(ParameterSetName = 'Notebook')]
    [Parameter(ParameterSetName = 'All')]
    [string]
    $OneNoteAppClientId = '812899b7-584c-4812-8aee-11d3e164d58b',

    [string]
    $User = 'me',

    [Parameter(Mandatory = $true, ParameterSetName = 'Notebook')]
    [string[]]
    $Notebook,

    [Parameter(Mandatory = $true, ParameterSetName = 'All')]
    [switch]
    $All,

    [Parameter(Mandatory = $true, ParameterSetName = 'Notebook')]
    [Parameter(Mandatory = $true, ParameterSetName = 'All')]
    $Path
)

#requires -Module MiniGraph
#requires -Module MarkdownPrince
```

Die Module MiniGraph und MarkdownPrince werden verwendet, um das Rad
nicht neu zu erfinden. Somit bleiben nur ein paar Schleifchen übrig, die
wir einbringen müssen. Gesagt, getan!

Erstmal besorgen wir uns alle Notebooks. Dies geht mit Hilfe der
Notebooks API. Da Filter unterstützt werden, können wir gezielt einzelne Notebooks abfragen.
Wenn ihr euch nicht sicher seid, schaut immer in die Doku unter <https://learn.microsoft.com/en-us/graph/overview>!

```powershell
$notebooks = if ($All.IsPresent)
{
    Invoke-GraphRequest -Query "$($User)/onenote/notebooks"
}
else
{
    $Notebook | ForEach-Object {
        Invoke-GraphRequest -Query "$($User)/onenote/notebooks?`$filter=displayName eq '$($_ -replace "'", "''")'"
    }
}
```

Da ich später im Code festgestellt habe, dass ich für eine Abfrage
doch gerne meinen Token hätte, gibt es hier einen kleinen Trick,
um modulinterne Daten abzurufen. Im Kontext des Moduls wird Code ausgeführt:

```powershell
$mg = Get-Module -Name MiniGraph
$token = & $mg { $script:token }
```

Merkt euch dieses Nugget! Ihr glaubt gar nicht, wie praktisch das manchmal sein kann.

Zurück zum Thema. Die jetzt folgenden Schleifen sind Basiswissen im
PowerShell-Bereich. Nach und nach holen wir uns alle Sektionen eines Notebooks, und
dann alle Seiten einer Sektion. Hierzu dienen uns die APIs sections und pages.

Bei den Seiten gibt es noch den kleinen Punkt "Eingebettete Inhalte" zu berücksichtigen.
Für mein kleines Projekt beschränke ich mich auf Bilder, die in img-Tags liegen. Hier
scheren wir dann etwas vom PowerShell-Basiswissen aus: Bei HTML handelt es sich
um wohlgeformte XML-Dokumente. Diese lassen sich am besten mit XPath abfragen. Kein
Herumgehampel mit Regular Expressions nötig!

Das beste: PowerShell gibt uns den HTML-Content der Seite bereits
korrekt deserialisiert als XmlDocument zurück. Die XPath-Query
`//img` duchforstet alle XML-Knoten (Elemente) und extrahiert alle Knoten vom Typ `img`.

Jedes Bild wird heruntergeladen und automatisch benannt, woraufhin der von MarkdownPrince
genutzte src-Tag neu geschrieben wird. Easy! Der Download der eingebetteten Ressourcen
erfolgt mit Invoke-RestMethod, da die Antwort Binär zurückkommt, und es für mich
schneller ging, den Token zu extrahieren, als einen Filestream zu schreiben. Das beste
Werkzeug für den Job!

```powershell
foreach ($book in $notebooks)
{
    $bookPath = Join-Path -Path $Path -ChildPath $book.displayName
    $sections = Invoke-GraphRequest -Query "$($User)/onenote/notebooks/$($book.id)/sections"
    if (-not (Test-Path -Path $bookPath))
    {
        $null = New-Item -Path $bookPath -ItemType Directory -Force
    }

    foreach ($section in $sections)
    {
        $sectionPath = Join-Path -Path $bookPath -ChildPath $section.displayName
        if (-not (Test-Path -Path $sectionPath))
        {
            $null = New-Item -Path $sectionPath -ItemType Directory -Force
        }
        $pages = Invoke-GraphRequest -Query "$($User)/onenote/sections/$($section.id)/pages"
        
        foreach ($page in $pages)
        {
            $pagePath = Join-Path -Path $sectionPath -ChildPath "$($page.title).md"
            $content = Invoke-GraphRequest -Query "$($User)/onenote/pages/$($page.id)/content"
            $imgCount = 0
            foreach ($image in $content.SelectNodes("//img"))
            {
                $header = @{
                    Authorization = "Bearer $token"
                }
                $imgName = '{0}_{1:d10}.png' -f $page.title, $imgCount
                $imgPath = Join-Path -Path $sectionPath -ChildPath resources
                if (-not (Test-Path -Path $imgPath))
                {
                    $null = New-Item -Path $imgPath -ItemType Directory -Force
                }

                Invoke-RestMethod -Method Get -Uri $image.'data-fullres-src' -Headers $header -OutFile (Join-Path $imgPath $imgName)

                $image.src = [uri]::EscapeUriString(('./resources/{1}' -f $section.displayName, $imgName))
            }

            $content.OuterXml | ConvertFrom-HTMLToMarkdown -DestinationPath $pagePath -Format
        }
    }
}
```

Den vollständigen Code findet ihr auf GitHub: <https://github.com/nyanhp/freeing-onenote>

Viel Spaß bei der Befreiung von OneNote! Macht mit eurem Markdown, was ihr wollt. Meine
persönliche Empfehlung ist ganz klar Obsidian, was ihr kostenfrei unter <https://obsidian.md>
herunterladen. Wenn ihr nach freier Software im Sinne der FSF sucht (GPL oder AGPL), ist
Trilium sicher eine gute Alternative.
