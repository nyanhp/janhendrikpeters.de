[CmdletBinding()]
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
    $OneDriveAppClientId = '812899b7-584c-4812-8aee-11d3e164d58b',

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

Connect-GraphDeviceCode -TenantId $TenantId -ClientId $OneDriveAppClientId
Set-GraphEndpoint -Type beta

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

if (-not (Test-Path $Path))
{
    $null = New-Item -Path $Path -ItemType Directory -Force
}

$mg = Get-Module -Name MiniGraph
$token = & $mg { $script:token }

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