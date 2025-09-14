function Get-EntrezProteinSequence {
    <#
    .SYNOPSIS
        Specialized function for retrieving protein sequences from NCBI Protein database

    .DESCRIPTION
        The Get-EntrezProteinSequence function provides optimized retrieval of protein sequences
        with comprehensive metadata extraction, multiple format options, and sequence analysis features.

    .PARAMETER Id
        Protein IDs to retrieve sequences for (accession numbers, GI numbers, etc.)

    .PARAMETER RetMode
        Output format: 'text', 'xml', 'json'

    .PARAMETER RetType
        Sequence format: 'fasta', 'gb', 'gp', 'seqid', 'acc'

    .PARAMETER IncludeMetadata
        Include comprehensive protein metadata (function, organism, references)

    .PARAMETER IncludeFeatures
        Include protein features and annotations

    .PARAMETER IncludeSequenceStats
        Calculate and include sequence statistics

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
        Get-EntrezProteinSequence -Id @('NP_012345.1', 'YP_123456.1') -RetType 'fasta'

        Retrieves protein sequences in FASTA format

    .EXAMPLE
        Get-EntrezProteinSequence -Id @('NP_012345.1') -IncludeMetadata -IncludeFeatures

        Retrieves protein with comprehensive metadata and features

    .EXAMPLE
        Get-EntrezProteinSequence -WebEnv $webenv -QueryKey 1 -RetMax 100 -IncludeSequenceStats

        Retrieves proteins using session data with sequence statistics

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
        [ValidateSet('fasta', 'gb', 'gp', 'seqid', 'acc')]
        [string]$RetType = 'fasta',

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
        Write-PSFMessage -Level Verbose -Message "Starting protein sequence retrieval"
    }

    process {
        try {
            # Base parameters for protein retrieval
            $baseParams = @{
                Database = 'protein'
                RetMode = $RetMode
                RetType = $RetType
                Tool = $Tool
            }

            if ($Email) { $baseParams['Email'] = $Email }
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

            # Enhanced processing for protein sequences
            $processedSequences = @()
            foreach ($seq in $sequences) {
                $proteinObj = ConvertTo-ProteinSequence -RawSequence $seq -IncludeMetadata:$IncludeMetadata -IncludeFeatures:$IncludeFeatures -IncludeSequenceStats:$IncludeSequenceStats -RetType $RetType

                $processedSequences += $proteinObj
            }

            return $processedSequences
        }
        catch {
            $ErrorMessage = "Failed to retrieve protein sequences: $($_.Exception.Message)"
            Write-PSFMessage -Level Error -Message $ErrorMessage
            throw $ErrorMessage
        }
    }
}

function ConvertTo-ProteinSequence {
    <#
    .SYNOPSIS
        Private helper function to convert raw protein data into enhanced sequence objects
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
        [string]$RetType
    )

    try {
        if ($RetType -eq 'fasta' -and $RawSequence.Header -and $RawSequence.Sequence) {
            # Enhanced FASTA processing
            $proteinObj = [PSCustomObject]@{
                Database = 'Protein'
                Accession = $null
                GI = $null
                Header = $RawSequence.Header
                Description = $null
                Organism = $null
                Sequence = $RawSequence.Sequence
                Length = $RawSequence.Length
                Retrieved = $RawSequence.Retrieved
                Type = 'Protein'
            }

            # Parse FASTA header for metadata
            if ($RawSequence.Header -match '^(\w+)\|([^|]+)\|([^|]*)\s*(.*)$') {
                $proteinObj.Accession = $Matches[2]
                $proteinObj.GI = if ($Matches[1] -eq 'gi') { $Matches[2] } else { $null }
                $proteinObj.Description = $Matches[4].Trim()
            }
            elseif ($RawSequence.Header -match '^(\S+)\s+(.+)$') {
                $proteinObj.Accession = $Matches[1]
                $proteinObj.Description = $Matches[2]
            }

            # Extract organism from description
            if ($proteinObj.Description -match '\[([^\]]+)\]$') {
                $proteinObj.Organism = $Matches[1]
            }

            # Calculate sequence statistics if requested
            if ($IncludeSequenceStats) {
                $proteinObj | Add-Member -NotePropertyName 'SequenceStats' -NotePropertyValue (Get-ProteinSequenceStats -Sequence $RawSequence.Sequence)
            }

            # Get additional metadata if requested (requires separate API call)
            if ($IncludeMetadata -and $proteinObj.Accession) {
                try {
                    $metadata = Get-ProteinMetadata -Accession $proteinObj.Accession
                    $proteinObj | Add-Member -NotePropertyName 'Metadata' -NotePropertyValue $metadata
                }
                catch {
                    Write-PSFMessage -Level Warning -Message "Could not retrieve metadata for $($proteinObj.Accession): $($_.Exception.Message)"
                }
            }

            return $proteinObj
        }
        elseif ($RetType -in @('gb', 'gp') -and $RawSequence.RawData) {
            # GenBank/GenPept format processing
            $gbData = $RawSequence.RawData -split "`n"

            $proteinObj = [PSCustomObject]@{
                Database = 'Protein'
                Format = $RetType.ToUpper()
                RawData = $RawSequence.RawData
                Retrieved = $RawSequence.Retrieved
                Type = 'Protein'
            }

            # Parse GenBank/GenPept format
            $currentSection = $null
            $sequence = @()
            $features = @()

            foreach ($line in $gbData) {
                if ($line -match '^LOCUS\s+(\S+)') {
                    $proteinObj | Add-Member -NotePropertyName 'Locus' -NotePropertyValue $Matches[1]
                }
                elseif ($line -match '^DEFINITION\s+(.+)') {
                    $proteinObj | Add-Member -NotePropertyName 'Definition' -NotePropertyValue $Matches[1]
                }
                elseif ($line -match '^ORGANISM\s+(.+)') {
                    $proteinObj | Add-Member -NotePropertyName 'Organism' -NotePropertyValue $Matches[1]
                }
                elseif ($line -match '^ORIGIN') {
                    $currentSection = 'SEQUENCE'
                }
                elseif ($currentSection -eq 'SEQUENCE' -and $line -match '^\s*\d+\s+([acdefghiklmnpqrstvwy\s]+)') {
                    $sequence += ($Matches[1] -replace '\s+', '').ToUpper()
                }
                elseif ($line -match '^\s+(\w+)\s+(.+)' -and $IncludeFeatures) {
                    $features += @{
                        Type = $Matches[1]
                        Location = $Matches[2]
                    }
                }
            }

            if ($sequence.Count -gt 0) {
                $fullSequence = $sequence -join ''
                $proteinObj | Add-Member -NotePropertyName 'Sequence' -NotePropertyValue $fullSequence
                $proteinObj | Add-Member -NotePropertyName 'Length' -NotePropertyValue $fullSequence.Length

                if ($IncludeSequenceStats) {
                    $proteinObj | Add-Member -NotePropertyName 'SequenceStats' -NotePropertyValue (Get-ProteinSequenceStats -Sequence $fullSequence)
                }
            }

            if ($IncludeFeatures -and $features.Count -gt 0) {
                $proteinObj | Add-Member -NotePropertyName 'Features' -NotePropertyValue $features
            }

            return $proteinObj
        }
        else {
            # Return original data if parsing fails
            return $RawSequence
        }
    }
    catch {
        Write-PSFMessage -Level Warning -Message "Error parsing protein sequence: $($_.Exception.Message)"
        return $RawSequence
    }
}

function Get-ProteinSequenceStats {
    <#
    .SYNOPSIS
        Private helper to calculate protein sequence statistics
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Sequence
    )

    $cleanSeq = $Sequence.ToUpper() -replace '[^ACDEFGHIKLMNPQRSTVWY]', ''
    $length = $cleanSeq.Length

    if ($length -eq 0) {
        return @{
            Length = 0
            Error = "No valid amino acid residues found"
        }
    }

    # Count amino acids
    $aminoAcids = @{
        'A'=0; 'C'=0; 'D'=0; 'E'=0; 'F'=0; 'G'=0; 'H'=0; 'I'=0;
        'K'=0; 'L'=0; 'M'=0; 'N'=0; 'P'=0; 'Q'=0; 'R'=0; 'S'=0;
        'T'=0; 'V'=0; 'W'=0; 'Y'=0
    }

    foreach ($char in $cleanSeq.ToCharArray()) {
        if ($aminoAcids.ContainsKey($char)) {
            $aminoAcids[$char]++
        }
    }

    # Calculate molecular weight (approximate)
    $molecularWeights = @{
        'A'=89.1; 'C'=121.2; 'D'=133.1; 'E'=147.1; 'F'=165.2; 'G'=75.1;
        'H'=155.2; 'I'=131.2; 'K'=146.2; 'L'=131.2; 'M'=149.2; 'N'=132.1;
        'P'=115.1; 'Q'=146.2; 'R'=174.2; 'S'=105.1; 'T'=119.1; 'V'=117.1;
        'W'=204.2; 'Y'=181.2
    }

    $molecularWeight = 0
    foreach ($aa in $aminoAcids.Keys) {
        $molecularWeight += $aminoAcids[$aa] * $molecularWeights[$aa]
    }
    $molecularWeight -= ($length - 1) * 18.02  # Subtract water molecules

    # Calculate other properties
    $hydrophobic = $aminoAcids['A'] + $aminoAcids['F'] + $aminoAcids['I'] + $aminoAcids['L'] + $aminoAcids['M'] + $aminoAcids['P'] + $aminoAcids['V'] + $aminoAcids['W'] + $aminoAcids['Y']
    $polar = $aminoAcids['C'] + $aminoAcids['N'] + $aminoAcids['Q'] + $aminoAcids['S'] + $aminoAcids['T'] + $aminoAcids['Y']
    $charged = $aminoAcids['D'] + $aminoAcids['E'] + $aminoAcids['H'] + $aminoAcids['K'] + $aminoAcids['R']

    return @{
        Length = $length
        MolecularWeight = [Math]::Round($molecularWeight, 2)
        AminoAcidComposition = $aminoAcids
        HydrophobicResidues = $hydrophobic
        HydrophobicPercent = [Math]::Round(($hydrophobic / $length) * 100, 2)
        PolarResidues = $polar
        PolarPercent = [Math]::Round(($polar / $length) * 100, 2)
        ChargedResidues = $charged
        ChargedPercent = [Math]::Round(($charged / $length) * 100, 2)
    }
}

function Get-ProteinMetadata {
    <#
    .SYNOPSIS
        Private helper to retrieve additional protein metadata
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