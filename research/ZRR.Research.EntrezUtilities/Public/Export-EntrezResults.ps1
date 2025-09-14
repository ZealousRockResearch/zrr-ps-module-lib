function Export-EntrezResults {
    <#
    .SYNOPSIS
        Exports Entrez search results and data to various formats for analysis and reporting

    .DESCRIPTION
        The Export-EntrezResults function provides comprehensive export capabilities for NCBI Entrez data.
        Supports multiple output formats including JSON, XML, CSV, TSV, Excel, and plain text.
        Handles large datasets with streaming and batch processing capabilities.

    .PARAMETER InputObject
        Entrez result objects to export (from search, summary, or fetch operations)

    .PARAMETER Path
        Output file path (extension determines format if Format not specified)

    .PARAMETER Format
        Export format: 'JSON', 'XML', 'CSV', 'TSV', 'Excel', 'Text', 'FASTA', 'BibTeX'

    .PARAMETER IncludeMetadata
        Include search metadata and timestamps in export

    .PARAMETER IncludeStatistics
        Include result statistics and summaries

    .PARAMETER FlattenStructure
        Flatten nested objects for tabular formats (CSV, TSV, Excel)

    .PARAMETER SelectedFields
        Specific fields to include in export (for tabular formats)

    .PARAMETER BatchSize
        Number of records to process in each batch (for large datasets)

    .PARAMETER Encoding
        Text encoding for output file

    .PARAMETER Compress
        Compress output file using ZIP compression

    .PARAMETER Overwrite
        Overwrite existing output file without prompting

    .PARAMETER PassThru
        Return export statistics without writing to file

    .PARAMETER Template
        Use predefined export template ('Publication', 'Sequence', 'Summary', 'Citation')

    .EXAMPLE
        $results = Search-EntrezDatabase -Database 'pubmed' -Term 'covid-19' -RetMax 100
        Export-EntrezResults -InputObject $results -Path 'covid_results.csv' -Format 'CSV'

        Export PubMed search results to CSV

    .EXAMPLE
        $articles = Get-EntrezPubMedArticle -Id @('12345678', '23456789')
        Export-EntrezResults -InputObject $articles -Path 'articles.json' -IncludeMetadata -Compress

        Export detailed articles to compressed JSON

    .EXAMPLE
        $sequences = Get-EntrezProteinSequence -Id @('NP_12345')
        Export-EntrezResults -InputObject $sequences -Format 'FASTA' -Path 'proteins.fasta'

        Export protein sequences to FASTA format

    .NOTES
        Author: Zealous Rock Research
        Requires: PSFramework for logging
        Optional: ImportExcel module for Excel export
    #>
    [CmdletBinding(DefaultParameterSetName = 'ToFile')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [ValidateNotNull()]
        [object[]]$InputObject,

        [Parameter(Mandatory, ParameterSetName = 'ToFile')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [ValidateSet('JSON', 'XML', 'CSV', 'TSV', 'Excel', 'Text', 'FASTA', 'BibTeX', 'Auto')]
        [string]$Format = 'Auto',

        [Parameter()]
        [switch]$IncludeMetadata,

        [Parameter()]
        [switch]$IncludeStatistics,

        [Parameter()]
        [switch]$FlattenStructure,

        [Parameter()]
        [string[]]$SelectedFields,

        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$BatchSize = 1000,

        [Parameter()]
        [ValidateSet('UTF8', 'ASCII', 'Unicode', 'UTF32')]
        [string]$Encoding = 'UTF8',

        [Parameter()]
        [switch]$Compress,

        [Parameter()]
        [switch]$Overwrite,

        [Parameter(ParameterSetName = 'PassThru')]
        [switch]$PassThru,

        [Parameter()]
        [ValidateSet('Publication', 'Sequence', 'Summary', 'Citation')]
        [string]$Template
    )

    begin {
        Write-PSFMessage -Level Verbose -Message "Starting Entrez results export"

        $allResults = @()
        $exportStats = @{
            TotalRecords = 0
            ProcessedRecords = 0
            SkippedRecords = 0
            ExportFormat = $Format
            StartTime = Get-Date
            EndTime = $null
            OutputPath = $Path
            Errors = @()
        }

        # Determine format from file extension if Auto
        if ($Format -eq 'Auto' -and $Path) {
            $extension = [System.IO.Path]::GetExtension($Path).ToLower()
            $Format = switch ($extension) {
                '.json' { 'JSON' }
                '.xml' { 'XML' }
                '.csv' { 'CSV' }
                '.tsv' { 'TSV' }
                '.txt' { 'Text' }
                '.xlsx' { 'Excel' }
                '.xls' { 'Excel' }
                '.fasta' { 'FASTA' }
                '.fa' { 'FASTA' }
                '.bib' { 'BibTeX' }
                default { 'JSON' }
            }
        }

        $exportStats.ExportFormat = $Format

        Write-PSFMessage -Level Verbose -Message "Export format determined: $Format"

        # Apply template settings
        if ($Template) {
            $templateSettings = Get-ExportTemplate -Template $Template
            if (-not $SelectedFields -and $templateSettings.Fields) {
                $SelectedFields = $templateSettings.Fields
            }
            if (-not $PSBoundParameters.ContainsKey('FlattenStructure') -and $templateSettings.FlattenStructure) {
                $FlattenStructure = $templateSettings.FlattenStructure
            }
        }
    }

    process {
        foreach ($result in $InputObject) {
            $allResults += $result
            $exportStats.TotalRecords++
        }
    }

    end {
        try {
            Write-PSFMessage -Level Verbose -Message "Processing $($allResults.Count) records for export"

            # Validate output path
            if ($Path -and -not $PassThru) {
                $outputDir = [System.IO.Path]::GetDirectoryName($Path)
                if ($outputDir -and -not (Test-Path $outputDir)) {
                    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
                    Write-PSFMessage -Level Verbose -Message "Created output directory: $outputDir"
                }

                if ((Test-Path $Path) -and -not $Overwrite) {
                    $response = Read-Host "File '$Path' exists. Overwrite? (Y/N)"
                    if ($response -notmatch '^[Yy]') {
                        throw "Export cancelled by user"
                    }
                }
            }

            # Process results based on format
            switch ($Format) {
                'JSON' {
                    $exportData = ConvertTo-JsonExport -Results $allResults -IncludeMetadata:$IncludeMetadata -IncludeStatistics:$IncludeStatistics

                    if ($PassThru) {
                        return $exportData
                    } else {
                        $exportData | ConvertTo-Json -Depth 10 | Out-File -FilePath $Path -Encoding $Encoding -Force
                    }
                }

                'XML' {
                    $exportData = ConvertTo-XmlExport -Results $allResults -IncludeMetadata:$IncludeMetadata

                    if ($PassThru) {
                        return $exportData
                    } else {
                        $exportData.Save($Path)
                    }
                }

                'CSV' {
                    $exportData = ConvertTo-TabularExport -Results $allResults -FlattenStructure:$FlattenStructure -SelectedFields $SelectedFields

                    if ($PassThru) {
                        return $exportData
                    } else {
                        $exportData | Export-Csv -Path $Path -NoTypeInformation -Encoding $Encoding -Force
                    }
                }

                'TSV' {
                    $exportData = ConvertTo-TabularExport -Results $allResults -FlattenStructure:$FlattenStructure -SelectedFields $SelectedFields

                    if ($PassThru) {
                        return $exportData
                    } else {
                        $exportData | ConvertTo-Csv -NoTypeInformation | ForEach-Object { $_ -replace ',', "`t" } | Out-File -FilePath $Path -Encoding $Encoding -Force
                    }
                }

                'Excel' {
                    $exportData = ConvertTo-TabularExport -Results $allResults -FlattenStructure:$FlattenStructure -SelectedFields $SelectedFields

                    if ($PassThru) {
                        return $exportData
                    } else {
                        Export-ToExcel -Data $exportData -Path $Path -IncludeMetadata:$IncludeMetadata
                    }
                }

                'FASTA' {
                    $exportData = ConvertTo-FastaExport -Results $allResults

                    if ($PassThru) {
                        return $exportData
                    } else {
                        $exportData -join "`n" | Out-File -FilePath $Path -Encoding $Encoding -Force
                    }
                }

                'BibTeX' {
                    $exportData = ConvertTo-BibTexExport -Results $allResults

                    if ($PassThru) {
                        return $exportData
                    } else {
                        $exportData -join "`n`n" | Out-File -FilePath $Path -Encoding $Encoding -Force
                    }
                }

                'Text' {
                    $exportData = ConvertTo-TextExport -Results $allResults -IncludeMetadata:$IncludeMetadata

                    if ($PassThru) {
                        return $exportData
                    } else {
                        $exportData -join "`n" | Out-File -FilePath $Path -Encoding $Encoding -Force
                    }
                }
            }

            $exportStats.ProcessedRecords = $allResults.Count
            $exportStats.EndTime = Get-Date

            # Compress output if requested
            if ($Compress -and $Path -and (Test-Path $Path)) {
                $compressedPath = "$Path.zip"
                Compress-Archive -Path $Path -DestinationPath $compressedPath -Force
                Remove-Item -Path $Path -Force
                $exportStats.OutputPath = $compressedPath
                Write-PSFMessage -Level Verbose -Message "Output compressed to: $compressedPath"
            }

            # Log export statistics
            if ($IncludeStatistics) {
                $duration = $exportStats.EndTime - $exportStats.StartTime
                Write-PSFMessage -Level Host -Message "Export completed: $($exportStats.ProcessedRecords) records in $($duration.TotalSeconds) seconds to $($exportStats.OutputPath)"
            }

            if ($PassThru) {
                return $exportStats
            }
        }
        catch {
            $exportStats.Errors += $_.Exception.Message
            $exportStats.EndTime = Get-Date

            $ErrorMessage = "Failed to export Entrez results: $($_.Exception.Message)"
            Write-PSFMessage -Level Error -Message $ErrorMessage

            if ($PassThru) {
                return $exportStats
            } else {
                throw $ErrorMessage
            }
        }
    }
}

function ConvertTo-JsonExport {
    param($Results, [switch]$IncludeMetadata, [switch]$IncludeStatistics)

    $exportObj = @{
        ExportInfo = @{
            ExportDate = Get-Date
            RecordCount = $Results.Count
            Format = 'JSON'
        }
        Data = $Results
    }

    if ($IncludeStatistics) {
        $exportObj.Statistics = Get-ResultStatistics -Results $Results
    }

    return $exportObj
}

function ConvertTo-XmlExport {
    param($Results, [switch]$IncludeMetadata)

    $xml = New-Object System.Xml.XmlDocument
    $root = $xml.CreateElement('EntrezExport')
    $xml.AppendChild($root) | Out-Null

    if ($IncludeMetadata) {
        $metaNode = $xml.CreateElement('ExportInfo')
        $metaNode.SetAttribute('ExportDate', (Get-Date).ToString())
        $metaNode.SetAttribute('RecordCount', $Results.Count)
        $root.AppendChild($metaNode) | Out-Null
    }

    $dataNode = $xml.CreateElement('Data')
    $root.AppendChild($dataNode) | Out-Null

    foreach ($result in $Results) {
        $recordNode = $xml.CreateElement('Record')
        Add-XmlProperties -XmlDocument $xml -ParentNode $recordNode -Object $result
        $dataNode.AppendChild($recordNode) | Out-Null
    }

    return $xml
}

function ConvertTo-TabularExport {
    param($Results, [switch]$FlattenStructure, [string[]]$SelectedFields)

    $exportData = @()

    foreach ($result in $Results) {
        if ($FlattenStructure) {
            $flattenedResult = ConvertTo-FlatObject -InputObject $result
        } else {
            $flattenedResult = $result
        }

        if ($SelectedFields) {
            $filteredResult = [PSCustomObject]@{}
            foreach ($field in $SelectedFields) {
                if ($flattenedResult.PSObject.Properties.Name -contains $field) {
                    $filteredResult | Add-Member -NotePropertyName $field -NotePropertyValue $flattenedResult.$field
                }
            }
            $exportData += $filteredResult
        } else {
            $exportData += $flattenedResult
        }
    }

    return $exportData
}

function ConvertTo-FastaExport {
    param($Results)

    $fastaLines = @()

    foreach ($result in $Results) {
        if ($result.Header -and $result.Sequence) {
            # Direct FASTA format object
            $fastaLines += ">$($result.Header)"
            $sequence = $result.Sequence
        } elseif ($result.Accession -and $result.Sequence) {
            # Sequence object with separate fields
            $header = $result.Accession
            if ($result.Description) {
                $header += " $($result.Description)"
            }
            $fastaLines += ">$header"
            $sequence = $result.Sequence
        } else {
            continue
        }

        # Split sequence into 80-character lines
        for ($i = 0; $i -lt $sequence.Length; $i += 80) {
            $line = $sequence.Substring($i, [Math]::Min(80, $sequence.Length - $i))
            $fastaLines += $line
        }
    }

    return $fastaLines
}

function ConvertTo-BibTexExport {
    param($Results)

    $bibEntries = @()
    $entryId = 1

    foreach ($result in $Results) {
        if ($result.Database -eq 'PubMed' -or $result.PMID) {
            $pmid = if ($result.PMID) { $result.PMID } else { $result.UID }
            $title = $result.Title -replace '[{}]', ''
            $authors = if ($result.Authors) {
                ($result.Authors | ForEach-Object {
                    if ($_.LastName -and $_.ForeName) {
                        "$($_.LastName), $($_.ForeName)"
                    } elseif ($_.CollectiveName) {
                        $_.CollectiveName
                    }
                }) -join ' and '
            } else { 'Unknown' }

            $journal = if ($result.Journal.Title) { $result.Journal.Title } else { 'Unknown' }
            $year = if ($result.Journal.PublicationDate -is [DateTime]) {
                $result.Journal.PublicationDate.Year
            } elseif ($result.Journal.PublicationDate) {
                $result.Journal.PublicationDate
            } else { 'Unknown' }

            $bibEntry = @"
@article{entry$entryId,
    title={$title},
    author={$authors},
    journal={$journal},
    year={$year},
    pmid={$pmid}
}
"@
            $bibEntries += $bibEntry
        }
        $entryId++
    }

    return $bibEntries
}

function ConvertTo-TextExport {
    param($Results, [switch]$IncludeMetadata)

    $textLines = @()

    if ($IncludeMetadata) {
        $textLines += "Entrez Export - $(Get-Date)"
        $textLines += "Records: $($Results.Count)"
        $textLines += "=" * 50
        $textLines += ""
    }

    foreach ($result in $Results) {
        $textLines += "Record: $($result.UID -or $result.PMID -or 'Unknown')"
        if ($result.Title) {
            $textLines += "Title: $($result.Title)"
        }
        if ($result.Authors) {
            $authors = ($result.Authors | ForEach-Object {
                if ($_.LastName -and $_.ForeName) {
                    "$($_.ForeName) $($_.LastName)"
                } elseif ($_.CollectiveName) {
                    $_.CollectiveName
                }
            }) -join ', '
            $textLines += "Authors: $authors"
        }
        if ($result.Abstract) {
            $textLines += "Abstract: $($result.Abstract)"
        }
        $textLines += "-" * 30
        $textLines += ""
    }

    return $textLines
}

function Get-ExportTemplate {
    param([string]$Template)

    switch ($Template) {
        'Publication' {
            return @{
                Fields = @('PMID', 'Title', 'Authors', 'Journal', 'PublicationDate', 'Abstract', 'DOI')
                FlattenStructure = $true
            }
        }
        'Sequence' {
            return @{
                Fields = @('Accession', 'Header', 'Description', 'Organism', 'Length', 'Sequence')
                FlattenStructure = $false
            }
        }
        'Summary' {
            return @{
                Fields = @('UID', 'Database', 'Title', 'Authors', 'PublicationDate')
                FlattenStructure = $true
            }
        }
        'Citation' {
            return @{
                Fields = @('PMID', 'FormattedCitation', 'DOI', 'Journal')
                FlattenStructure = $true
            }
        }
    }
}

function ConvertTo-FlatObject {
    param($InputObject, $Prefix = '')

    $output = [PSCustomObject]@{}

    foreach ($property in $InputObject.PSObject.Properties) {
        $name = if ($Prefix) { "$Prefix.$($property.Name)" } else { $property.Name }

        if ($property.Value -is [PSCustomObject] -or $property.Value -is [hashtable]) {
            $flattened = ConvertTo-FlatObject -InputObject $property.Value -Prefix $name
            foreach ($flatProperty in $flattened.PSObject.Properties) {
                $output | Add-Member -NotePropertyName $flatProperty.Name -NotePropertyValue $flatProperty.Value
            }
        } elseif ($property.Value -is [array]) {
            $output | Add-Member -NotePropertyName $name -NotePropertyValue ($property.Value -join '; ')
        } else {
            $output | Add-Member -NotePropertyName $name -NotePropertyValue $property.Value
        }
    }

    return $output
}

function Export-ToExcel {
    param($Data, $Path, [switch]$IncludeMetadata)

    try {
        if (Get-Module -ListAvailable -Name ImportExcel) {
            Import-Module ImportExcel -Force
            $Data | Export-Excel -Path $Path -WorksheetName "EntrezData" -AutoSize -FreezeTopRow
        } else {
            # Fallback to CSV if ImportExcel not available
            Write-PSFMessage -Level Warning -Message "ImportExcel module not available, exporting as CSV instead"
            $csvPath = [System.IO.Path]::ChangeExtension($Path, '.csv')
            $Data | Export-Csv -Path $csvPath -NoTypeInformation -Force
        }
    }
    catch {
        Write-PSFMessage -Level Warning -Message "Excel export failed, falling back to CSV: $($_.Exception.Message)"
        $csvPath = [System.IO.Path]::ChangeExtension($Path, '.csv')
        $Data | Export-Csv -Path $csvPath -NoTypeInformation -Force
    }
}

function Add-XmlProperties {
    param($XmlDocument, $ParentNode, $Object, $PropertyName = '')

    if ($Object -is [PSCustomObject] -or $Object -is [hashtable]) {
        foreach ($property in $Object.PSObject.Properties) {
            $element = $XmlDocument.CreateElement($property.Name)
            Add-XmlProperties -XmlDocument $XmlDocument -ParentNode $element -Object $property.Value -PropertyName $property.Name
            $ParentNode.AppendChild($element) | Out-Null
        }
    } elseif ($Object -is [array]) {
        foreach ($item in $Object) {
            $element = $XmlDocument.CreateElement('Item')
            Add-XmlProperties -XmlDocument $XmlDocument -ParentNode $element -Object $item
            $ParentNode.AppendChild($element) | Out-Null
        }
    } else {
        $ParentNode.InnerText = [string]$Object
    }
}

function Get-ResultStatistics {
    param($Results)

    $stats = @{
        TotalRecords = $Results.Count
        Databases = @{}
        RecordTypes = @{}
        DateRange = @{
            Earliest = $null
            Latest = $null
        }
    }

    foreach ($result in $Results) {
        # Count by database
        if ($result.Database) {
            if ($stats.Databases.ContainsKey($result.Database)) {
                $stats.Databases[$result.Database]++
            } else {
                $stats.Databases[$result.Database] = 1
            }
        }

        # Count by record type
        if ($result.Type) {
            if ($stats.RecordTypes.ContainsKey($result.Type)) {
                $stats.RecordTypes[$result.Type]++
            } else {
                $stats.RecordTypes[$result.Type] = 1
            }
        }

        # Track date range
        $date = $null
        if ($result.PublicationDate -is [DateTime]) {
            $date = $result.PublicationDate
        } elseif ($result.Journal.PublicationDate -is [DateTime]) {
            $date = $result.Journal.PublicationDate
        } elseif ($result.Retrieved -is [DateTime]) {
            $date = $result.Retrieved
        }

        if ($date) {
            if (-not $stats.DateRange.Earliest -or $date -lt $stats.DateRange.Earliest) {
                $stats.DateRange.Earliest = $date
            }
            if (-not $stats.DateRange.Latest -or $date -gt $stats.DateRange.Latest) {
                $stats.DateRange.Latest = $date
            }
        }
    }

    return $stats
}