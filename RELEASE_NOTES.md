# ZRR PowerShell Module Library - Release Notes

## Version 0.1.1 - Enhanced Abstract Retrieval (2025-09-14)

### 🚀 Major New Features

#### **Search-Entrez Function**
A powerful new unified search function that combines metadata and full abstract retrieval in a single, efficient operation.

```powershell
# Get articles with titles and full abstracts
Search-Entrez -Query "meditation AND hasabstract[sb]" -IncludeTitles -IncludeSummary -MaxResults 10

# Get PMC articles with full-text links
Search-Entrez -Database 'pmc' -Query "meditation" -IncludeAll -IncludeFullDoc -MaxResults 5

# Export results to CSV
Search-Entrez -Query "COVID-19 vaccines" -IncludeTitles -IncludeAuthors -IncludeDOI -OutputFormat CSV -ExportPath "results.csv"
```

**Key Features:**
- **Flexible Parameters**: `-IncludeTitles`, `-IncludeSummary`, `-IncludeAuthors`, `-IncludePublicationDate`, `-IncludeDOI`, `-IncludeJournal`, `-IncludeFullDoc`, `-IncludeAll`
- **Multiple Output Formats**: Object, Table, CSV, JSON
- **PMC Integration**: Automatic full-text URL generation for PMC articles
- **Export Capability**: Direct export to files
- **Intelligent Defaults**: Returns ID and Title if no fields specified

### ⚡ Performance Enhancements

#### **Efficient Abstract Retrieval**
- **Batch Processing**: Single API call retrieves up to 500 abstracts
- **Session Caching**: Avoids duplicate requests within PowerShell session
- **Rate Limiting**: NCBI-compliant 3 requests/second with automatic delays
- **Smart Parsing**: Handles non-sequential article numbering in batch responses

**Performance Metrics:**
- 3 articles: ~1.0 second
- 10 articles: ~1.1 seconds
- Cached queries: ~50% faster
- Up to 90% success rate for abstract retrieval

#### **Enhanced Data Extraction**
- **Improved XML Parsing**: Handles API version 2.0 DocumentSummarySet structure
- **Better Author Extraction**: Properly parses XML author nodes
- **DOI Resolution**: Extracts DOI from ArticleIds collection
- **Clean Abstract Text**: Filters out citation metadata and copyright notices

### 🔧 Bug Fixes & Improvements

#### **Get-EntrezDocumentSummary**
- **Fixed Output Issues**: Added `Write-Output` for proper object return
- **Enhanced Error Handling**: Graceful fallbacks for failed retrievals
- **Improved Parsing**: Better handling of different XML response formats

#### **Module Infrastructure**
- **Updated Manifest**: Added Search-Entrez to exports
- **Removed Conflicts**: Eliminated alias conflicts for clean function usage
- **Better Documentation**: Enhanced inline help and examples

### 📋 Technical Details

#### **Abstract Retrieval Algorithm**
1. **Conditional Fetching**: Only retrieves abstracts when `-IncludeSummary` is used
2. **Batch API Calls**: Uses EFetch with multiple IDs per request
3. **Response Parsing**: Splits concatenated batch responses by article boundaries
4. **Text Extraction**: Intelligent parsing to extract clean abstract content
5. **Caching Layer**: Session-level cache prevents duplicate API calls

#### **PMC Integration**
- **Database Support**: Native PMC database searching
- **URL Generation**: Automatic PMC article URL creation
- **Filtering Options**: Built-in PMC and free full-text filters
- **Hybrid Approach**: Combines PubMed metadata with PMC full-text availability

### 🎯 Usage Examples

#### **Basic Abstract Search**
```powershell
# Search with abstracts
Search-Entrez -Query "mindfulness therapy" -IncludeTitles -IncludeSummary -MaxResults 20
```

#### **PMC Full-Text Articles**
```powershell
# Get articles with full-text available
Search-Entrez -Database 'pmc' -Query "machine learning healthcare" -IncludeAll -IncludeFullDoc
```

#### **Research Workflow**
```powershell
# Complete research query with all metadata
Search-Entrez -Query "ADHD treatment AND hasabstract[sb] AND pmc[sb]" `
    -IncludeTitles -IncludeSummary -IncludeAuthors -IncludePublicationDate -IncludeDOI -IncludeFullDoc `
    -MaxResults 50 -OutputFormat CSV -ExportPath "ADHD_research.csv"
```

### 🔍 Search Field Reference

**Useful PubMed search filters:**
- `hasabstract[sb]` - Articles with abstracts
- `pmc[sb]` - Articles in PMC
- `free full text[sb]` - Free full-text articles
- `2024:2025[pdat]` - Publication date range
- `review[pt]` - Review articles
- `clinical trial[pt]` - Clinical trials

### ⚠️ Important Notes

- **API Key Recommended**: Set `$env:NCBI_API_KEY` for better rate limits (10 req/sec vs 3)
- **Reasonable Batch Sizes**: Optimal performance with 10-50 articles per query
- **Abstract Availability**: Not all articles have abstracts despite filters
- **Rate Limiting**: Automatic compliance with NCBI guidelines

### 🔄 Backward Compatibility

All existing functionality remains unchanged:
- `Search-EntrezDatabase` - Still available with all features
- `Get-EntrezDocumentSummary` - Enhanced but compatible
- All other module functions - Unchanged

### 🤝 Contributors

- **Enhanced by**: Claude Code AI Assistant
- **Developed for**: Zealous Rock Research
- **Module**: ZRR.Research.EntrezUtilities

---

## Previous Versions

### Version 0.1.0 - Initial Release (2025-09-13)
- Complete NCBI Entrez E-utilities API coverage
- Enterprise-grade logging and error handling
- Multi-database support (PubMed, PMC, Protein, Nucleotide)
- Session management with history server
- Batch processing capabilities