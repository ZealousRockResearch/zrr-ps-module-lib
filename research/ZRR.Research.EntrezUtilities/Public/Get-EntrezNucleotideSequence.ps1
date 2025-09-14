function Get-EntrezNucleotideSequence {
    <#
    .SYNOPSIS
        Specialized function for retrieving nucleotide sequences from NCBI Nucleotide database

    .DESCRIPTION
        The Get-EntrezNucleotideSequence function provides optimized retrieval of nucleotide sequences
        with comprehensive metadata extraction, strand selection, and sequence analysis features.

    .PARAMETER Id
        Nucleotide IDs to retrieve sequences for (accession numbers, GI numbers, etc.)

    .PARAMETER RetMode
        Output format: 'text', 'xml', 'json'

    .PARAMETER RetType
        Sequence format: 'fasta', 'gb', 'ft', 'seqid', 'acc'

    .PARAMETER Strand
        DNA strand to retrieve (1 for plus strand, 2 for minus strand)

    .PARAMETER SeqStart
        Starting position in sequence (1-based)

    .PARAMETER SeqStop
        Ending position in sequence (1-based)

    .PARAMETER IncludeMetadata
        Include comprehensive nucleotide metadata (organism, taxonomy, references)

    .PARAMETER IncludeFeatures
        Include sequence features and annotations

    .PARAMETER IncludeSequenceStats
        Calculate and include nucleotide composition and statistics

    .PARAMETER ComplexityFilter
        Filter sequences by complexity level (0-4)

    .PARAMETER WebEnv
        Web environment string from previous search

    .PARAMETER QueryKey
        Query key from previous search

    .PARAMETER RetStart
        Starting position in result set (0-based)

    .PARAMETER RetMax
        Maximum number of records to retrieve

    .PARAMETER Tool
        Tool name for API usage tracking

    .PARAMETER Email
        Email address for API usage tracking

    .EXAMPLE
        Get-EntrezNucleotideSequence -Id @('NM_012345.3', 'NC_123456.1') -RetType 'fasta'

        Retrieves nucleotide sequences in FASTA format

    .EXAMPLE
        Get-EntrezNucleotideSequence -Id @('NM_012345.3') -Strand 1 -SeqStart 100 -SeqStop 500

        Retrieves specific region of plus strand

    .EXAMPLE
        Get-EntrezNucleotideSequence -Id @('NC_123456.1') -IncludeMetadata -IncludeFeatures -IncludeSequenceStats

        Retrieves sequence with comprehensive annotations and statistics

    .NOTES
        Author: Zealous Rock Research
        Requires: PSFramework for logging
        NCBI API: https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByIds')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByIds', ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter(ParameterSetName = 'BySession')]
        [ValidateNotNullOrEmpty()]
        [string]$WebEnv,

        [Parameter(ParameterSetName = 'BySession')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$QueryKey,

        [Parameter()]
        [ValidateSet('text', 'xml', 'json')]
        [string]$RetMode = 'text',

        [Parameter()]
        [ValidateSet('fasta', 'gb', 'ft', 'seqid', 'acc')]
        [string]$RetType = 'fasta',

        [Parameter()]
        [ValidateSet(1, 2)]
        [int]$Strand,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$SeqStart,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$SeqStop,

        [Parameter()]
        [switch]$IncludeMetadata,

        [Parameter()]
        [switch]$IncludeFeatures,

        [Parameter()]
        [switch]$IncludeSequenceStats,

        [Parameter()]
        [ValidateRange(0, 4)]
        [int]$ComplexityFilter,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$RetStart = 0,

        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$RetMax = 500,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Tool = $Script:ModuleConfig.ModuleName,

        [Parameter()]
        [ValidatePattern('^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')]
        [string]$Email
    )

    begin {
        Write-PSFMessage -Level Verbose -Message "Starting nucleotide sequence retrieval"

        # Validate sequence range parameters
        if ($SeqStart -and $SeqStop -and $SeqStart -gt $SeqStop) {
            throw "SeqStart ($SeqStart) cannot be greater than SeqStop ($SeqStop)"
        }
    }

    process {
        try {
            # Base parameters for nucleotide retrieval
            $baseParams = @{
                Database = 'nucleotide'
                RetMode = $RetMode
                RetType = $RetType
                Tool = $Tool
            }

            if ($Email) { $baseParams['Email'] = $Email }
            if ($Strand) { $baseParams['Strand'] = $Strand }
            if ($SeqStart) { $baseParams['SeqStart'] = $SeqStart }
            if ($SeqStop) { $baseParams['SeqStop'] = $SeqStop }
            if ($PSBoundParameters.ContainsKey('ComplexityFilter')) { $baseParams['Complexity'] = $ComplexityFilter }

            if ($PSCmdlet.ParameterSetName -eq 'ByIds') {
                $baseParams['Id'] = $Id
            } else {
                $baseParams['WebEnv'] = $WebEnv
                $baseParams['QueryKey'] = $QueryKey
                $baseParams['RetStart'] = $RetStart
                $baseParams['RetMax'] = $RetMax
            }

            # Get base sequence data
            $sequences = Get-EntrezDataRecord @baseParams

            # Enhanced processing for nucleotide sequences
            $processedSequences = @()
            foreach ($seq in $sequences) {
                $nucleotideObj = ConvertTo-NucleotideSequence -RawSequence $seq -IncludeMetadata:$IncludeMetadata -IncludeFeatures:$IncludeFeatures -IncludeSequenceStats:$IncludeSequenceStats -RetType $RetType -Strand $Strand -SeqStart $SeqStart -SeqStop $SeqStop

                $processedSequences += $nucleotideObj
            }

            return $processedSequences
        }
        catch {
            $ErrorMessage = "Failed to retrieve nucleotide sequences: $($_.Exception.Message)"
            Write-PSFMessage -Level Error -Message $ErrorMessage
            throw $ErrorMessage
        }
    }
}

function ConvertTo-NucleotideSequence {
    <#
    .SYNOPSIS
        Private helper function to convert raw nucleotide data into enhanced sequence objects
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $RawSequence,

        [Parameter()]
        [switch]$IncludeMetadata,

        [Parameter()]
        [switch]$IncludeFeatures,

        [Parameter()]
        [switch]$IncludeSequenceStats,

        [Parameter(Mandatory)]
        [string]$RetType,

        [Parameter()]
        [int]$Strand,

        [Parameter()]
        [int]$SeqStart,

        [Parameter()]
        [int]$SeqStop
    )

    try {
        if ($RetType -eq 'fasta' -and $RawSequence.Header -and $RawSequence.Sequence) {
            # Enhanced FASTA processing
            $nucleotideObj = [PSCustomObject]@{
                Database = 'Nucleotide'
                Accession = $null
                GI = $null
                Header = $RawSequence.Header
                Description = $null
                Organism = $null
                Sequence = $RawSequence.Sequence
                Length = $RawSequence.Length
                Retrieved = $RawSequence.Retrieved
                Type = 'Nucleotide'
                Strand = $Strand
                Region = if ($SeqStart -and $SeqStop) { "$SeqStart-$SeqStop" } else { $null }
            }

            # Parse FASTA header for metadata
            if ($RawSequence.Header -match '^(\w+)\|([^|]+)\|([^|]*)\s*(.*)$') {
                $nucleotideObj.Accession = $Matches[2]
                $nucleotideObj.GI = if ($Matches[1] -eq 'gi') { $Matches[2] } else { $null }
                $nucleotideObj.Description = $Matches[4].Trim()
            }
            elseif ($RawSequence.Header -match '^(\S+)\s+(.+)$') {
                $nucleotideObj.Accession = $Matches[1]
                $nucleotideObj.Description = $Matches[2]
            }

            # Extract organism from description
            if ($nucleotideObj.Description -match '\[([^\]]+)\]$') {
                $nucleotideObj.Organism = $Matches[1]
            }

            # Determine sequence type
            $nucleotideObj | Add-Member -NotePropertyName 'SequenceType' -NotePropertyValue (Get-NucleotideSequenceType -Sequence $RawSequence.Sequence)

            # Calculate sequence statistics if requested
            if ($IncludeSequenceStats) {
                $nucleotideObj | Add-Member -NotePropertyName 'SequenceStats' -NotePropertyValue (Get-NucleotideSequenceStats -Sequence $RawSequence.Sequence)
            }

            # Get additional metadata if requested (requires separate API call)
            if ($IncludeMetadata -and $nucleotideObj.Accession) {
                try {
                    $metadata = Get-NucleotideMetadata -Accession $nucleotideObj.Accession
                    $nucleotideObj | Add-Member -NotePropertyName 'Metadata' -NotePropertyValue $metadata
                }
                catch {
                    Write-PSFMessage -Level Warning -Message "Could not retrieve metadata for $($nucleotideObj.Accession): $($_.Exception.Message)"
                }
            }

            return $nucleotideObj
        }
        elseif ($RetType -eq 'gb' -and $RawSequence.RawData) {
            # GenBank format processing
            $gbData = $RawSequence.RawData -split "`n"

            $nucleotideObj = [PSCustomObject]@{
                Database = 'Nucleotide'
                Format = 'GenBank'
                RawData = $RawSequence.RawData
                Retrieved = $RawSequence.Retrieved
                Type = 'Nucleotide'
            }

            # Parse GenBank format
            $currentSection = $null
            $sequence = @()
            $features = @()
            $inFeatures = $false

            foreach ($line in $gbData) {
                if ($line -match '^LOCUS\s+(\S+)\s+(\d+)\s+bp\s+(\S+)') {
                    $nucleotideObj | Add-Member -NotePropertyName 'Locus' -NotePropertyValue $Matches[1]
                    $nucleotideObj | Add-Member -NotePropertyName 'Length' -NotePropertyValue ([int]$Matches[2])
                    $nucleotideObj | Add-Member -NotePropertyName 'MoleculeType' -NotePropertyValue $Matches[3]
                }
                elseif ($line -match '^DEFINITION\s+(.+)') {
                    $nucleotideObj | Add-Member -NotePropertyName 'Definition' -NotePropertyValue $Matches[1]
                }
                elseif ($line -match '^ORGANISM\s+(.+)') {
                    $nucleotideObj | Add-Member -NotePropertyName 'Organism' -NotePropertyValue $Matches[1]
                }
                elseif ($line -match '^FEATURES') {
                    $inFeatures = $true
                }
                elseif ($line -match '^ORIGIN') {
                    $currentSection = 'SEQUENCE'
                    $inFeatures = $false
                }
                elseif ($currentSection -eq 'SEQUENCE' -and $line -match '^\s*\d+\s+([acgtryswkmbdhvn\s]+)') {
                    $sequence += ($Matches[1] -replace '\s+', '').ToUpper()
                }
                elseif ($inFeatures -and $line -match '^\s+(\w+)\s+(.+)' -and $IncludeFeatures) {
                    $features += @{
                        Type = $Matches[1]
                        Location = $Matches[2]
                    }
                }
            }

            if ($sequence.Count -gt 0) {
                $fullSequence = $sequence -join ''
                $nucleotideObj | Add-Member -NotePropertyName 'Sequence' -NotePropertyValue $fullSequence
                $nucleotideObj | Add-Member -NotePropertyName 'SequenceType' -NotePropertyValue (Get-NucleotideSequenceType -Sequence $fullSequence)

                if ($IncludeSequenceStats) {
                    $nucleotideObj | Add-Member -NotePropertyName 'SequenceStats' -NotePropertyValue (Get-NucleotideSequenceStats -Sequence $fullSequence)
                }
            }

            if ($IncludeFeatures -and $features.Count -gt 0) {
                $nucleotideObj | Add-Member -NotePropertyName 'Features' -NotePropertyValue $features
            }

            return $nucleotideObj
        }
        else {
            # Return original data if parsing fails
            return $RawSequence
        }
    }
    catch {
        Write-PSFMessage -Level Warning -Message "Error parsing nucleotide sequence: $($_.Exception.Message)"
        return $RawSequence
    }
}

function Get-NucleotideSequenceType {
    <#
    .SYNOPSIS
        Private helper to determine nucleotide sequence type
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Sequence
    )

    $cleanSeq = $Sequence.ToUpper() -replace '[^ACGTRYSWKMBDHVN]', ''
    $length = $cleanSeq.Length

    if ($length -eq 0) {
        return 'Unknown'
    }

    # Count nucleotides
    $aCount = ($cleanSeq.ToCharArray() | Where-Object { $_ -eq 'A' }).Count
    $tCount = ($cleanSeq.ToCharArray() | Where-Object { $_ -eq 'T' }).Count
    $gCount = ($cleanSeq.ToCharArray() | Where-Object { $_ -eq 'G' }).Count
    $cCount = ($cleanSeq.ToCharArray() | Where-Object { $_ -eq 'C' }).Count
    $uCount = ($cleanSeq.ToCharArray() | Where-Object { $_ -eq 'U' }).Count

    # Basic classification
    if ($uCount -gt 0 -and $tCount -eq 0) {
        return 'RNA'
    } elseif ($tCount -gt 0 -and $uCount -eq 0) {
        return 'DNA'
    } else {
        return 'DNA'  # Default assumption
    }
}

function Get-NucleotideSequenceStats {
    <#
    .SYNOPSIS
        Private helper to calculate nucleotide sequence statistics
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Sequence
    )

    $cleanSeq = $Sequence.ToUpper() -replace '[^ACGTRYSWKMBDHVN]', ''
    $length = $cleanSeq.Length

    if ($length -eq 0) {
        return @{
            Length = 0
            Error = "No valid nucleotides found"
        }
    }

    # Count nucleotides
    $nucleotides = @{
        'A'=0; 'T'=0; 'G'=0; 'C'=0; 'U'=0; 'R'=0; 'Y'=0; 'S'=0; 'W'=0; 'K'=0; 'M'=0; 'B'=0; 'D'=0; 'H'=0; 'V'=0; 'N'=0
    }

    foreach ($char in $cleanSeq.ToCharArray()) {
        if ($nucleotides.ContainsKey($char)) {
            $nucleotides[$char]++
        }
    }

    # Calculate GC content
    $gcCount = $nucleotides['G'] + $nucleotides['C']
    $gcContent = if ($length -gt 0) { ($gcCount / $length) * 100 } else { 0 }

    # Calculate AT content
    $atCount = $nucleotides['A'] + $nucleotides['T'] + $nucleotides['U']
    $atContent = if ($length -gt 0) { ($atCount / $length) * 100 } else { 0 }

    # Determine sequence type
    $sequenceType = if ($nucleotides['U'] -gt 0 -and $nucleotides['T'] -eq 0) { 'RNA' } else { 'DNA' }

    # Calculate melting temperature (rough estimation for short sequences)
    $meltingTemp = if ($length -le 14) {
        # Wallace rule for short sequences
        ($nucleotides['A'] + $nucleotides['T'] + $nucleotides['U']) * 2 + ($nucleotides['G'] + $nucleotides['C']) * 4
    } elseif ($length -le 50) {
        # More accurate formula for medium sequences
        81.5 + 16.6 * [Math]::Log10(0.05) + 0.41 * $gcContent - 675 / $length
    } else {
        $null  # Too long for simple estimation
    }

    return @{
        Length = $length
        SequenceType = $sequenceType
        NucleotideComposition = @{
            A = $nucleotides['A']
            T = $nucleotides['T']
            G = $nucleotides['G']
            C = $nucleotides['C']
            U = $nucleotides['U']
        }
        GCContent = [Math]::Round($gcContent, 2)
        ATContent = [Math]::Round($atContent, 2)
        AmbiguousBases = $nucleotides['R'] + $nucleotides['Y'] + $nucleotides['S'] + $nucleotides['W'] + $nucleotides['K'] + $nucleotides['M'] + $nucleotides['B'] + $nucleotides['D'] + $nucleotides['H'] + $nucleotides['V'] + $nucleotides['N']
        MeltingTemperature = if ($meltingTemp) { [Math]::Round($meltingTemp, 1) } else { $null }
    }
}

function Get-NucleotideMetadata {
    <#
    .SYNOPSIS
        Private helper to retrieve additional nucleotide metadata
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Accession
    )

    # This would typically make an additional API call to get detailed metadata
    # For now, returning basic structure
    return @{
        Accession = $Accession
        Note = "Extended metadata retrieval not implemented in this version"
    }
}